import XCTest

@testable import ClaudeUsageMonitor

/// Each case here stands for a way this app has broken, or could break without
/// anyone noticing: the API reports quota *consumed* while the UI shows what is
/// left, `percent` has arrived as both an integer and a float, and a window the
/// API declines to quantify must not render as an empty — that is, exhausted —
/// ring.
final class UsageLimitTests: XCTestCase {

    /// Shaped like a real response: snake_case keys, an integer `percent`
    /// alongside a float sibling, a model-scoped window, and top-level fields
    /// this app has no use for.
    private let payload = Data(
        """
        {
          "limits": [
            {
              "kind": "session",
              "percent": 37,
              "utilization": 37.4,
              "resets_at": "2026-09-05T12:00:00.123456Z"
            },
            {
              "kind": "weekly_all",
              "percent": 12,
              "resets_at": "2026-09-08T00:00:00Z"
            },
            {
              "kind": "weekly_scoped",
              "percent": 80,
              "resets_at": "2026-09-08T00:00:00Z",
              "scope": { "surface": "claude_code", "model": { "display_name": "Fable" } }
            }
          ],
          "unrelated_window": null,
          "another_unrelated_window": { "percent": 5 }
        }
        """.utf8)

    private func decodeResponse(_ data: Data) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    private func decodeLimit(_ json: String) throws -> UsageLimit {
        try JSONDecoder().decode(UsageLimit.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesEveryWindowAndIgnoresUnknownTopLevelFields() throws {
        let limits = try XCTUnwrap(decodeResponse(payload).limits)

        XCTAssertEqual(limits.count, 3)
        XCTAssertEqual(limits.map(\.kind), ["session", "weekly_all", "weekly_scoped"])
    }

    func testPercentAcceptsBothIntegerAndFloat() throws {
        // The endpoint has sent both. Narrowing this to Int would throw on the
        // next response that carries a fraction.
        let integer = try decodeLimit(#"{ "kind": "session", "percent": 37 }"#)
        let float = try decodeLimit(#"{ "kind": "session", "percent": 37.4 }"#)

        XCTAssertEqual(integer.percent, 37)
        XCTAssertEqual(try XCTUnwrap(float.percent), 37.4, accuracy: 0.0001)
    }

    func testResponseWithoutLimitsDecodesRatherThanThrows() throws {
        // A 200 that carries no windows is a display problem, not a parse error.
        XCTAssertNil(try decodeResponse(Data("{}".utf8)).limits)
    }

    // MARK: - Remaining quota

    func testRemainingIsTheComplementOfConsumedQuota() throws {
        let limits = try XCTUnwrap(decodeResponse(payload).limits)

        // 37% consumed is 63% left — not 37%.
        XCTAssertEqual(limits[0].remainingPercentage, 63)
        XCTAssertEqual(limits[1].remainingPercentage, 88)
        XCTAssertEqual(limits[2].remainingPercentage, 20)
    }

    func testRemainingIsNilWhenTheAPIQuantifiesNothing() throws {
        // The view skips a nil ring. Substituting 0 here would tell the user
        // their quota is gone.
        let limit = try decodeLimit(#"{ "kind": "session", "resets_at": "2026-09-08T00:00:00Z" }"#)

        XCTAssertNil(limit.remainingPercentage)
    }

    func testRemainingRoundsAndStaysWithinZeroToOneHundred() throws {
        let rounded = try decodeLimit(#"{ "percent": 37.5 }"#)
        let overspent = try decodeLimit(#"{ "percent": 120 }"#)
        let negative = try decodeLimit(#"{ "percent": -10 }"#)

        XCTAssertEqual(rounded.remainingPercentage, 62)
        XCTAssertEqual(overspent.remainingPercentage, 0)
        XCTAssertEqual(negative.remainingPercentage, 100)
    }

    // MARK: - Labels

    func testEachKindOfWindowIsNamed() throws {
        let limits = try XCTUnwrap(decodeResponse(payload).limits)
        let english = Strings(language: .english)

        XCTAssertEqual(limits[0].label(english), "5 hours")
        XCTAssertEqual(limits[1].label(english), "7 days")
        // A model-scoped window is named after the model it constrains.
        XCTAssertEqual(limits[2].label(english), "Fable")
    }

    func testScopedWindowFallsBackWhenTheModelIsUnnamed() throws {
        let english = Strings(language: .english)
        let unnamed = try decodeLimit(#"{ "kind": "weekly_scoped", "percent": 1 }"#)
        let unknown = try decodeLimit(#"{ "kind": "some_new_window", "percent": 1 }"#)
        let kindless = try decodeLimit(#"{ "percent": 1 }"#)

        XCTAssertEqual(unnamed.label(english), "Weekly (scoped)")
        // An unfamiliar window still shows up, labelled with whatever it calls
        // itself, rather than being dropped.
        XCTAssertEqual(unknown.label(english), "some_new_window")
        XCTAssertEqual(kindless.label(english), "Unknown")
    }

    // MARK: - Reset timestamps

    func testResetDateParsesWithAndWithoutFractionalSeconds() throws {
        let limits = try XCTUnwrap(decodeResponse(payload).limits)

        // Both spellings appear in the same response. The API sends microseconds
        // and ISO8601DateFormatter keeps only milliseconds — harmless, since the
        // UI renders these to the minute, but worth stating rather than
        // discovering.
        XCTAssertEqual(
            try XCTUnwrap(limits[0].resetDate).timeIntervalSince1970,
            1_788_609_600.123,
            accuracy: 0.0005)
        XCTAssertEqual(
            try XCTUnwrap(limits[1].resetDate).timeIntervalSince1970,
            1_788_825_600,
            accuracy: 0.0001)
    }

    func testResetDateIsNilWhenTheTimestampIsMissingOrUnreadable() throws {
        let missing = try decodeLimit(#"{ "kind": "session", "percent": 1 }"#)
        let unreadable = try decodeLimit(#"{ "kind": "session", "resets_at": "next Tuesday" }"#)

        XCTAssertNil(missing.resetDate)
        XCTAssertNil(unreadable.resetDate)
        XCTAssertEqual(unreadable.resetTimeString, "--")
    }
}
