import Foundation

/// Japanese and English without a resource bundle.
///
/// `build.sh` assembles the .app from two files; a `.lproj` tree would mean
/// carrying a third and keeping it in sync by hand. With a dozen strings, a
/// value that holds both languages is smaller than the machinery to look them
/// up — and it lets the tests pin a language instead of mutating the process's
/// locale.
struct Strings {

    enum Language {
        case japanese
        case english

        /// Japanese for a Japanese system, English for everything else.
        static var preferred: Language {
            let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return code.hasPrefix("ja") ? .japanese : .english
        }
    }

    let language: Language

    static let current = Strings(language: .preferred)

    private func pick(_ japanese: String, _ english: String) -> String {
        language == .japanese ? japanese : english
    }

    // MARK: - Quota windows

    var sessionWindow: String { pick("5時間", "5 hours") }
    var weeklyWindow: String { pick("7日間", "7 days") }
    var scopedWindow: String { pick("週(限定)", "Weekly (scoped)") }
    var unknownWindow: String { pick("不明", "Unknown") }

    // MARK: - Popover

    var loading: String { pick("読み込み中...", "Loading…") }
    var noWindows: String { pick("表示できる枠がありません", "No quota windows to show") }
    var refresh: String { pick("更新", "Refresh") }
    var refreshing: String { pick("更新中...", "Refreshing…") }
    var quit: String { pick("終了", "Quit") }
    var never: String { pick("未取得", "never") }

    func updated(_ time: String) -> String {
        pick("更新: \(time)", "Updated \(time)")
    }

    /// Spoken by VoiceOver for the menu bar item, whose colour is the message.
    func menuBarDescription(remaining: Int?) -> String {
        guard let remaining else {
            return pick("Claude 使用量: 未取得", "Claude usage: no data")
        }
        return pick(
            "Claude 使用量: 残り \(remaining)パーセント",
            "Claude usage: \(remaining) percent left")
    }

    /// Spoken by VoiceOver in place of the ring, which is unreadable to it.
    func ringDescription(window: String, remaining: Int, resets: String) -> String {
        pick(
            "\(window) 残り \(remaining)パーセント、リセット \(resets)",
            "\(window): \(remaining) percent left, resets at \(resets)")
    }

    // MARK: - Failures

    var noCredentials: String {
        pick(
            "Claude Code の認証情報が見つかりません",
            "No Claude Code credentials found")
    }

    var sessionExpired: String {
        pick(
            "Claude Code の認証が切れました。自動更新を試みています。回復しない場合はターミナルで claude を1回起動してください",
            """
            Your Claude Code session expired. Trying to refresh it — if that does not \
            help, run `claude` once in a terminal.
            """)
    }

    func rateLimited(retryAfter: TimeInterval?) -> String {
        guard let retryAfter, retryAfter > 0 else {
            return pick(
                "アクセス集中で一時的に取得できません。次の自動更新で回復します",
                "Rate limited. The next refresh should recover.")
        }
        let minutes = max(1, Int((retryAfter / 60).rounded(.up)))
        return pick(
            "アクセス集中で一時的に取得できません。約\(minutes)分後に再取得します",
            "Rate limited. Retrying in about \(minutes) min.")
    }

    func networkFailure(_ message: String) -> String {
        pick("通信エラー: \(message)", "Network error: \(message)")
    }

    func apiFailure(status: Int) -> String {
        pick("APIエラー (HTTP \(status))", "API error (HTTP \(status))")
    }

    func decodingFailure(_ message: String) -> String {
        pick("データ解析エラー: \(message)", "Could not read the response: \(message)")
    }
}
