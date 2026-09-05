import SwiftUI
import XCTest

@testable import ClaudeUsageMonitor

/// Colour is the entire message this app sends. A glance at the menu bar tells
/// you whether you are fine or nearly out, and nothing else does — so swapping
/// two of these thresholds is a serious bug that changes no layout, throws no
/// error, and would otherwise ship unnoticed.
final class QuotaColorTests: XCTestCase {

    // MARK: - Menu bar

    func testMenuBarIsGreenWhileThereIsPlentyLeft() {
        XCTAssertEqual(QuotaColor.menuBar(remaining: 100), .green)
        XCTAssertEqual(QuotaColor.menuBar(remaining: 61), .green)
        // The boundary itself: 60 is comfortable, not a warning.
        XCTAssertEqual(QuotaColor.menuBar(remaining: 60), .green)
    }

    func testMenuBarTurnsYellowBelowSixty() {
        XCTAssertEqual(QuotaColor.menuBar(remaining: 59), .yellow)
        XCTAssertEqual(QuotaColor.menuBar(remaining: 40), .yellow)
    }

    func testMenuBarTurnsRedBelowForty() {
        XCTAssertEqual(QuotaColor.menuBar(remaining: 39), .red)
        XCTAssertEqual(QuotaColor.menuBar(remaining: 0), .red)
    }

    // MARK: - Rings

    func testRingIsGreenFromFiftyUp() {
        XCTAssertEqual(QuotaColor.ring(remaining: 100), .green)
        XCTAssertEqual(QuotaColor.ring(remaining: 50), .green)
    }

    func testRingTurnsOrangeBelowFifty() {
        XCTAssertEqual(QuotaColor.ring(remaining: 49), .orange)
        XCTAssertEqual(QuotaColor.ring(remaining: 20), .orange)
    }

    func testRingTurnsRedBelowTwenty() {
        XCTAssertEqual(QuotaColor.ring(remaining: 19), .red)
        XCTAssertEqual(QuotaColor.ring(remaining: 0), .red)
    }

    // MARK: - The relationship between the two

    func testTheMenuBarWarnsBeforeTheRingsDo() {
        // Deliberate: the menu bar is glanceable and the rings are not, so the
        // menu bar has to raise the alarm first. If someone "unifies" these two
        // scales, this is the case that should stop them.
        let alarming = (0...100).filter { QuotaColor.menuBar(remaining: $0) != .green }
        let alarmingRings = (0...100).filter { QuotaColor.ring(remaining: $0) != .green }

        XCTAssertGreaterThan(alarming.count, alarmingRings.count)
        XCTAssertTrue(Set(alarmingRings).isSubset(of: Set(alarming)))
    }
}
