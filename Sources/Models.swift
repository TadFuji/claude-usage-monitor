import Foundation

struct UsageResponse: Codable {
    let limits: [UsageLimit]?
}

struct UsageLimit: Codable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    struct Scope: Codable {
        let model: Model?
        let surface: String?

        struct Model: Codable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind, percent, scope
        case resetsAt = "resets_at"
    }

    /// A window the app does not recognise still gets a caption — whatever the
    /// API calls it — rather than being dropped from the display.
    func label(_ strings: Strings = .current) -> String {
        switch kind {
        case "session": return strings.sessionWindow
        case "weekly_all": return strings.weeklyWindow
        case "weekly_scoped": return scope?.model?.displayName ?? strings.scopedWindow
        default: return kind ?? strings.unknownWindow
        }
    }

    // The API's `percent` is the quota already consumed (0–100), so the UI shows
    // what is left. A missing figure stays nil: the caller skips the ring rather
    // than drawing an empty one, which would read as "exhausted".
    var remainingPercentage: Int? {
        guard let percent else { return nil }
        return min(100, max(0, 100 - Int(percent.rounded())))
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let todayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        if let date = Self.iso8601WithFractionalSeconds.date(from: resetsAt) { return date }
        return Self.iso8601.date(from: resetsAt)
    }

    var resetTimeString: String {
        guard let date = resetDate else { return "--" }
        if Calendar.current.isDateInToday(date) {
            return Self.todayTimeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }
}
