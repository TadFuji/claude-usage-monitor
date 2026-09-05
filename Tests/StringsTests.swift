import XCTest

@testable import ClaudeUsageMonitor

/// The app ships two languages as a value rather than a resource bundle, which
/// makes one mistake easy: adding a string and returning the same text for both
/// languages. These cases exist to catch that, and to pin the failure messages
/// people will paste into a bug report.
final class StringsTests: XCTestCase {

    private let japanese = Strings(language: .japanese)
    private let english = Strings(language: .english)

    func testEveryVisibleStringIsTranslated() {
        let pairs: [(String, String)] = [
            (japanese.sessionWindow, english.sessionWindow),
            (japanese.weeklyWindow, english.weeklyWindow),
            (japanese.scopedWindow, english.scopedWindow),
            (japanese.unknownWindow, english.unknownWindow),
            (japanese.loading, english.loading),
            (japanese.noWindows, english.noWindows),
            (japanese.refresh, english.refresh),
            (japanese.refreshing, english.refreshing),
            (japanese.quit, english.quit),
            (japanese.never, english.never),
            (japanese.noCredentials, english.noCredentials),
            (japanese.sessionExpired, english.sessionExpired),
            (japanese.updated("10:00"), english.updated("10:00")),
            (japanese.apiFailure(status: 500), english.apiFailure(status: 500)),
            (japanese.rateLimited(retryAfter: nil), english.rateLimited(retryAfter: nil)),
        ]

        for (ja, en) in pairs {
            XCTAssertFalse(ja.isEmpty)
            XCTAssertFalse(en.isEmpty)
            XCTAssertNotEqual(ja, en, "\"\(ja)\" was left untranslated")
        }
    }

    func testWindowLabelsFollowTheChosenLanguage() throws {
        let session = try JSONDecoder().decode(
            UsageLimit.self, from: Data(#"{ "kind": "session", "percent": 10 }"#.utf8))

        XCTAssertEqual(session.label(japanese), "5時間")
        XCTAssertEqual(session.label(english), "5 hours")
    }

    func testAModelScopedWindowKeepsTheModelNameInBothLanguages() throws {
        let scoped = try JSONDecoder().decode(
            UsageLimit.self,
            from: Data(
                #"{ "kind": "weekly_scoped", "percent": 10, "scope": { "model": { "display_name": "Opus" } } }"#
                    .utf8))

        // A model name is a proper noun; it is not translated in either.
        XCTAssertEqual(scoped.label(japanese), "Opus")
        XCTAssertEqual(scoped.label(english), "Opus")
    }

    func testTheRateLimitMessageNamesTheWaitWhenTheServerGaveOne() {
        // Rounded up, so "about 1 min" never means "any moment now".
        XCTAssertTrue(english.rateLimited(retryAfter: 90).contains("2"))
        XCTAssertTrue(japanese.rateLimited(retryAfter: 90).contains("2"))
        XCTAssertTrue(english.rateLimited(retryAfter: 30).contains("1"))
    }

    func testFailuresCarryTheUnderlyingDetail() {
        // Whatever the app says, the reason has to survive into the message —
        // it is the only diagnostic a user can paste into an issue.
        XCTAssertTrue(english.networkFailure("timed out").contains("timed out"))
        XCTAssertTrue(japanese.networkFailure("timed out").contains("timed out"))
        XCTAssertTrue(english.apiFailure(status: 503).contains("503"))
        XCTAssertTrue(english.decodingFailure("bad key").contains("bad key"))
    }

    func testErrorsDescribeThemselvesInTheChosenLanguage() {
        XCTAssertEqual(
            UsageServiceError.noToken.description(english), english.noCredentials)
        XCTAssertEqual(
            UsageServiceError.invalidResponse(401).description(japanese), japanese.sessionExpired)
        XCTAssertEqual(
            UsageServiceError.rateLimited(retryAfter: 60).description(english),
            english.rateLimited(retryAfter: 60))
        XCTAssertEqual(
            UsageServiceError.invalidResponse(500).description(english),
            english.apiFailure(status: 500))
    }

    func testAccessibilityTextCarriesTheNumberInBothLanguages() {
        XCTAssertTrue(japanese.menuBarDescription(remaining: 42).contains("42"))
        XCTAssertTrue(english.menuBarDescription(remaining: 42).contains("42"))
        XCTAssertFalse(japanese.menuBarDescription(remaining: nil).isEmpty)
    }
}
