import XCTest

@testable import ClaudeUsageMonitor

/// `Retry-After` is the one piece of the response that changes what the app
/// does next rather than what it shows. Getting it wrong in the lenient
/// direction — treating an unreadable header as "retry immediately" — turns a
/// rate limit into a hot loop against someone else's server.
final class RetryAfterTests: XCTestCase {

    func testSecondsAreTakenAtFaceValue() {
        XCTAssertEqual(parseRetryAfter("30"), 30)
        XCTAssertEqual(parseRetryAfter("3600"), 3600)
        // Servers pad headers with whitespace more often than you would hope.
        XCTAssertEqual(parseRetryAfter("  45  "), 45)
    }

    func testAnHTTPDateIsConvertedToAWait() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: Date().addingTimeInterval(120))

        let delay = try XCTUnwrap(parseRetryAfter(header))

        XCTAssertEqual(delay, 120, accuracy: 5)
    }

    func testNothingUsableMeansNoGuidance() {
        // Not "wait zero seconds" — no guidance, so the caller keeps its own
        // interval instead of hammering the endpoint.
        XCTAssertNil(parseRetryAfter(nil))
        XCTAssertNil(parseRetryAfter(""))
        XCTAssertNil(parseRetryAfter("   "))
        XCTAssertNil(parseRetryAfter("soon"))
        XCTAssertNil(parseRetryAfter("Mon, 32 Foo 2026 99:99:99 GMT"))
    }

    func testAWaitThatHasAlreadyPassedIsIgnored() {
        XCTAssertNil(parseRetryAfter("0"))
        XCTAssertNil(parseRetryAfter("-60"))
        XCTAssertNil(parseRetryAfter("Thu, 01 Jan 1970 00:00:00 GMT"))
    }
}
