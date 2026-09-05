import SwiftUI
import XCTest

@testable import ClaudeUsageMonitor

/// Not a test: this regenerates the README screenshots from the real views, so
/// the pictures cannot quietly drift away from the code. It skips unless asked,
/// and CI never asks.
///
///     SCREENSHOT_OUTPUT=docs swift test --filter Screenshot
///
/// Every value below is fixed, so re-running this on the same machine produces
/// the same bytes and an unchanged file rather than a pointless binary diff.
/// (Times are formatted in the local zone, so a machine in another zone will
/// render different clock faces.)
@MainActor
final class ScreenshotTests: XCTestCase {

    func testRegenerateReadmeScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT"] else {
            throw XCTSkip("Set SCREENSHOT_OUTPUT to a directory to regenerate the screenshots.")
        }

        // Plausible mid-week numbers: a comfortable session, half the week
        // gone, and a model-scoped window that is the one actually running out.
        let json = """
            {
              "limits": [
                { "kind": "session", "percent": 27, "resets_at": "2026-09-08T09:40:00Z" },
                { "kind": "weekly_all", "percent": 46, "resets_at": "2026-09-11T02:40:00Z" },
                { "kind": "weekly_scoped", "percent": 81, "resets_at": "2026-09-11T02:40:00Z",
                  "scope": { "model": { "display_name": "Opus" } } }
              ]
            }
            """

        let viewModel = UsageViewModel(startPolling: false)
        viewModel.usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        viewModel.lastUpdated = Date(timeIntervalSince1970: 1_788_609_600)

        let base = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        try render(
            viewModel, language: .english, scheme: .light,
            to: base.appendingPathComponent("screenshot.png"))
        try render(
            viewModel, language: .english, scheme: .dark,
            to: base.appendingPathComponent("screenshot-dark.png"))
        try render(
            viewModel, language: .japanese, scheme: .light,
            to: base.appendingPathComponent("screenshot-ja.png"))
    }

    private func render(
        _ viewModel: UsageViewModel,
        language: Strings.Language,
        scheme: ColorScheme,
        to url: URL
    ) throws {
        // The popover draws on the system's menu material, which does not exist
        // off screen — so the background is stated explicitly here rather than
        // rendering onto transparency.
        let background = scheme == .dark ? Color(white: 0.13) : Color(white: 0.97)
        let view =
            UsageDetailView(viewModel: viewModel, strings: Strings(language: language))
            .frame(width: 260)
            .background(background)
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "the view produced no image")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
