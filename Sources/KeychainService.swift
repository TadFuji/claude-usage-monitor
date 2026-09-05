import Foundation

enum KeychainService {
    // Read through /usr/bin/security rather than SecItemCopyMatching. The CLI
    // rewrites this item with `security add-generic-password -U` on every token
    // refresh (~8h), and that write resets the item's ACL partition list to
    // `apple-tool:` alone — wiping the cdhash entry "Always Allow" had added for
    // this app, so the next read re-prompted. /usr/bin/security is Apple-signed
    // and matches `apple-tool:`, so it survives those rewrites; it is also how
    // the CLI itself reads the item back.
    static func getOAuthToken() -> String? {
        guard let data = readItem(),
            let object = try? JSONSerialization.jsonObject(with: data),
            let json = object as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            return nil
        }

        return token
    }

    private static func readItem() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        // Launched directly, not via a shell: the secret comes back on stdout and
        // never touches argv or the process list.
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Watchdog: `security` puts up its own modal if the login keychain is
        // locked, and this call is synchronous inside the poll loop — an
        // unattended dialog would wedge it exactly the way the old in-process
        // read did. Kill it and report no token instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if process.isRunning { process.terminate() }
        }

        // Drain before waiting: a full pipe buffer would deadlock the child.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        // -w emits the password followed by a newline.
        return String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .data(using: .utf8)
    }
}
