import Foundation

enum UsageServiceError: Error, LocalizedError {
    case noToken
    case networkError(String)
    case invalidResponse(Int)
    /// Kept apart from `invalidResponse(429)` because it carries the delay the
    /// server asked for, which the polling loop honours.
    case rateLimited(retryAfter: TimeInterval?)
    case decodingError(String)

    var errorDescription: String? {
        description(Strings.current)
    }

    func description(_ strings: Strings) -> String {
        switch self {
        case .noToken:
            return strings.noCredentials
        case .networkError(let message):
            return strings.networkFailure(message)
        case .invalidResponse(401):
            return strings.sessionExpired
        case .rateLimited(let retryAfter):
            return strings.rateLimited(retryAfter: retryAfter)
        case .invalidResponse(let code):
            return strings.apiFailure(status: code)
        case .decodingError(let message):
            return strings.decodingFailure(message)
        }
    }

    /// The delay this failure asks the caller to wait, if it asked for one.
    var retryAfter: TimeInterval? {
        guard case .rateLimited(let retryAfter) = self else { return nil }
        return retryAfter
    }
}

/// `Retry-After` is either a number of seconds or an HTTP date. Only the first
/// form has ever been observed here; an unparseable header is treated as no
/// guidance rather than as zero, which would busy-loop.
func parseRetryAfter(_ header: String?) -> TimeInterval? {
    guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
        return nil
    }
    if let seconds = TimeInterval(header) {
        return seconds > 0 ? seconds : nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: header) else { return nil }
    let seconds = date.timeIntervalSinceNow
    return seconds > 0 ? seconds : nil
}

// This app never touches the OAuth refresh token itself (doing so could desync
// the CLI's credentials). Instead it runs the claude CLI once — a minimal haiku
// prompt — which refreshes the Keychain token as a side effect. Verified to
// work on 2026-08-31.
// Launched from the Finder, the app's own working directory is "/", and the CLI
// files each run's transcript under the cwd — littering ~/.claude/projects/-/.
// Give it a directory this app owns instead. Deliberately outside the MainActor
// type below, so the background closure that spawns the CLI can read it.
private let cliWorkingDirectory: URL? = {
    guard
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    else { return nil }
    let directory = base.appendingPathComponent("ClaudeUsageMonitor", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // A missing directory — or a file sitting where the directory should be —
    // would make Process.run() throw on every attempt, and this is computed
    // once. Fall back to inheriting the app's cwd rather than breaking the
    // refresh outright.
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue ? directory : nil
}()

@MainActor
enum TokenRefresher {
    private static var lastAttempt: Date?
    // The token lives ~8h; retry at most every 30 minutes.
    private static let minInterval: TimeInterval = 1800

    static func tryRefresh() async -> Bool {
        if let last = lastAttempt, Date().timeIntervalSince(last) < minInterval {
            return false
        }
        lastAttempt = Date()
        return await runCLI()
    }

    private static func runCLI() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                // Login shell so the user's PATH finds claude wherever it lives;
                // `exec` replaces that shell with the CLI so the watchdog below
                // signals the CLI itself instead of leaving it orphaned.
                process.arguments = [
                    "-lc", "exec claude -p 'reply with exactly: ok' --model haiku",
                ]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                if let directory = cliWorkingDirectory {
                    process.currentDirectoryURL = directory
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                // Watchdog: a hung CLI must not wedge the polling loop.
                // terminate() alone is not enough against a CLI that traps
                // SIGTERM for cleanup — waitUntilExit() would block forever — so
                // escalate to SIGKILL. Defensive: the CLI has not been observed
                // doing that. The kill
                // reaches the CLI itself, not any grandchildren it spawned;
                // those can linger, but they no longer hold up this loop.
                DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
}

enum UsageService {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let clientVersion = "2.0.32"
    private static let userAgent = "claude-code/\(clientVersion)"
    private static let oauthBetaHeader = "oauth-2025-04-20"

    /// - Parameter allowRefresh: whether a `401` may spend one CLI refresh and
    ///   retry. The retry passes `false`, which is what stops this recursing:
    ///   the 30-minute throttle inside `TokenRefresher` is a budget, not a
    ///   termination guarantee.
    static func fetch(allowRefresh: Bool = true) async throws -> UsageResponse {
        guard let token = KeychainService.getOAuthToken() else {
            throw UsageServiceError.noToken
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                let header = httpResponse.value(forHTTPHeaderField: "Retry-After")
                throw UsageServiceError.rateLimited(retryAfter: parseRetryAfter(header))
            }
            // An expired token is the routine failure (tokens live ~8h). Let the
            // real CLI refresh the Keychain, then retry once — the throttle in
            // TokenRefresher keeps this from looping.
            if httpResponse.statusCode == 401, allowRefresh, await TokenRefresher.tryRefresh() {
                return try await fetch(allowRefresh: false)
            }
            throw UsageServiceError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decodingError(error.localizedDescription)
        }
    }
}
