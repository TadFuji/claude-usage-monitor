import Combine
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private var pollingTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 300  // 5 minutes
    private let fetch: () async throws -> UsageResponse

    // The app polls from the moment it launches. Tests construct the model
    // without a network loop, and substitute a fetch that fails on demand.
    init(
        startPolling: Bool = true,
        fetch: @escaping () async throws -> UsageResponse = { try await UsageService.fetch() }
    ) {
        self.fetch = fetch
        if startPolling { startAutoRefresh() }
    }

    deinit {
        pollingTask?.cancel()
    }

    var sessionRemaining: Int? {
        usage?.limits?.first(where: { $0.kind == "session" })?.remainingPercentage
    }

    /// The windows worth drawing. A window the API declined to quantify is left
    /// out rather than drawn as an empty ring, which would read as "exhausted".
    var visibleLimits: [UsageLimit] {
        (usage?.limits ?? []).filter { $0.remainingPercentage != nil }
    }

    /// What VoiceOver says for the menu bar item, where the colour carries the
    /// meaning and the glyph carries none.
    var menuBarAccessibilityText: String {
        Strings.current.menuBarDescription(remaining: sessionRemaining)
    }

    // A transient fetch error keeps showing the last known figure; "C--" only
    // when there has never been data.
    var menuBarText: String {
        if let session = sessionRemaining {
            return "C\(session)"
        }
        if errorMessage != nil {
            return "C--"
        }
        return isLoading ? "C.." : "C--"
    }

    func lastUpdatedText(_ strings: Strings = .current) -> String {
        guard let date = lastUpdated else { return strings.never }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    func startAutoRefresh() {
        pollingTask?.cancel()
        let interval = refreshInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                // Each fetch decides when the next one happens: a rate-limited
                // server gets the pause it asked for instead of another poll in
                // five minutes.
                let delay = await self?.fetchOnce() ?? interval
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() {
        // Restart the loop: triggers an immediate fetch, cancels any in-flight
        // request, and resets the auto-refresh interval.
        startAutoRefresh()
    }

    /// One fetch, returning how long to wait before the next one. Internal so
    /// tests can drive it directly with a substituted `fetch`.
    @discardableResult
    func fetchOnce() async -> TimeInterval {
        isLoading = true
        errorMessage = nil
        var delay = refreshInterval
        do {
            let response = try await fetch()
            usage = response
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            if Task.isCancelled { return delay }
            errorMessage = error.localizedDescription
            delay = Self.nextDelay(after: error, pollInterval: refreshInterval)
        }
        isLoading = false
        return delay
    }

    /// Never poll faster than the interval, and never stall longer than an hour
    /// however large a `Retry-After` the server sends.
    static let maximumBackoff: TimeInterval = 3600

    static func nextDelay(after error: Error, pollInterval: TimeInterval) -> TimeInterval {
        guard let retryAfter = (error as? UsageServiceError)?.retryAfter else {
            return pollInterval
        }
        return min(max(retryAfter, pollInterval), maximumBackoff)
    }
}
