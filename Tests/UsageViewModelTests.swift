import XCTest

@testable import ClaudeUsageMonitor

/// The menu bar is the only part of this app most people ever look at, and it
/// has one job: never claim to know something it does not. These cases pin the
/// states it can be in, the rule that a failed poll must not erase a figure
/// already on screen, and how long the app waits before trying again.
@MainActor
final class UsageViewModelTests: XCTestCase {

    /// Matches `refreshInterval` in the view model.
    private let pollInterval: TimeInterval = 300

    private func response(
        session: Double?, weekly: Double? = nil, scopedWithoutPercent: Bool = false
    )
        throws -> UsageResponse
    {
        var windows: [String] = []
        if let session {
            windows.append(#"{ "kind": "session", "percent": \#(session) }"#)
        }
        if let weekly {
            windows.append(#"{ "kind": "weekly_all", "percent": \#(weekly) }"#)
        }
        if scopedWithoutPercent {
            windows.append(#"{ "kind": "weekly_scoped", "resets_at": "2026-09-08T00:00:00Z" }"#)
        }
        let json = #"{ "limits": [\#(windows.joined(separator: ","))] }"#
        return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    private func makeViewModel(
        fetch: @escaping () async throws -> UsageResponse = { throw UsageServiceError.noToken }
    ) -> UsageViewModel {
        UsageViewModel(startPolling: false, fetch: fetch)
    }

    // MARK: - What the menu bar says

    func testMenuBarShowsWhatIsLeftOfTheSessionWindow() throws {
        let viewModel = makeViewModel()
        viewModel.usage = try response(session: 25, weekly: 90)

        // The session window, not the first one and not the worst one.
        XCTAssertEqual(viewModel.sessionRemaining, 75)
        XCTAssertEqual(viewModel.menuBarText, "C75")
    }

    func testMenuBarSaysLoadingOnlyBeforeTheFirstResult() {
        let viewModel = makeViewModel()
        viewModel.isLoading = true

        XCTAssertEqual(viewModel.menuBarText, "C..")
    }

    func testMenuBarReportsNoDataWhenThereIsNoSessionWindow() throws {
        let viewModel = makeViewModel()
        viewModel.usage = try response(session: nil, weekly: 40)

        XCTAssertNil(viewModel.sessionRemaining)
        XCTAssertEqual(viewModel.menuBarText, "C--")
    }

    func testVoiceOverGetsTheNumberTheColourStandsFor() throws {
        let viewModel = makeViewModel()
        viewModel.usage = try response(session: 25)

        // The glyph is the same shape at every level; only its colour changes,
        // and VoiceOver cannot see colour.
        XCTAssertTrue(viewModel.menuBarAccessibilityText.contains("75"))
    }

    // MARK: - Which rings get drawn

    func testWindowsWithoutAFigureAreLeftOutRatherThanDrawnEmpty() throws {
        let viewModel = makeViewModel()
        viewModel.usage = try response(session: 25, weekly: 90, scopedWithoutPercent: true)

        // Three windows came back; the one the API declined to quantify is not
        // drawn, because an empty ring reads as "exhausted".
        XCTAssertEqual(viewModel.usage?.limits?.count, 3)
        XCTAssertEqual(viewModel.visibleLimits.count, 2)
        XCTAssertEqual(viewModel.visibleLimits.map(\.kind), ["session", "weekly_all"])
    }

    func testNoWindowsAtAllIsNotAnError() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.visibleLimits.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Fetching

    func testAFailedFetchKeepsTheFigureAlreadyOnScreen() async throws {
        let good = try response(session: 25)
        var shouldFail = false
        let viewModel = makeViewModel {
            if shouldFail { throw UsageServiceError.networkError("The request timed out.") }
            return good
        }

        await viewModel.fetchOnce()
        XCTAssertEqual(viewModel.menuBarText, "C75")

        shouldFail = true
        await viewModel.fetchOnce()

        // A dropped poll is not news. Replacing a good figure with "C--" is.
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.menuBarText, "C75")
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    func testASuccessfulFetchClearsAnEarlierError() async throws {
        let good = try response(session: 25)
        var shouldFail = true
        let viewModel = makeViewModel {
            if shouldFail { throw UsageServiceError.noToken }
            return good
        }

        await viewModel.fetchOnce()
        XCTAssertNotNil(viewModel.errorMessage)

        shouldFail = false
        await viewModel.fetchOnce()
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTimestampIsAbsentUntilTheFirstSuccessfulFetch() {
        let viewModel = makeViewModel()

        XCTAssertNil(viewModel.lastUpdated)
        XCTAssertEqual(viewModel.lastUpdatedText(Strings(language: .english)), "never")
        XCTAssertEqual(viewModel.lastUpdatedText(Strings(language: .japanese)), "未取得")
    }

    // MARK: - Backing off

    func testAnOrdinaryFailureLeavesThePollIntervalAlone() async {
        let viewModel = makeViewModel { throw UsageServiceError.networkError("offline") }

        let delay = await viewModel.fetchOnce()

        XCTAssertEqual(delay, pollInterval)
    }

    func testARateLimitedServerGetsThePauseItAskedFor() async {
        let viewModel = makeViewModel {
            throw UsageServiceError.rateLimited(retryAfter: 900)
        }

        let delay = await viewModel.fetchOnce()

        XCTAssertEqual(delay, 900)
    }

    func testTheServerCannotMakeUsPollFasterThanTheInterval() {
        let error = UsageServiceError.rateLimited(retryAfter: 5)

        XCTAssertEqual(
            UsageViewModel.nextDelay(after: error, pollInterval: pollInterval), pollInterval)
    }

    func testTheServerCannotStallUsIndefinitely() {
        let error = UsageServiceError.rateLimited(retryAfter: 86_400)

        XCTAssertEqual(
            UsageViewModel.nextDelay(after: error, pollInterval: pollInterval),
            UsageViewModel.maximumBackoff)
    }

    func testARateLimitWithoutGuidanceFallsBackToTheInterval() {
        let error = UsageServiceError.rateLimited(retryAfter: nil)

        XCTAssertEqual(
            UsageViewModel.nextDelay(after: error, pollInterval: pollInterval), pollInterval)
    }
}
