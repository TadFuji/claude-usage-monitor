import SwiftUI

@main
struct ClaudeUsageMonitorApp: App {
    @StateObject private var viewModel = UsageViewModel()

    init() {}

    var body: some Scene {
        MenuBarExtra {
            UsageDetailView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        // The default .menu style renders the content as a real NSMenu, which
        // drops shapes and stack layout. Rings need a real SwiftUI surface.
        .menuBarExtraStyle(.window)
    }
}

/// The two colour scales, kept out of the views so they can be tested. The menu
/// bar warns earlier than the rings do, because for most of the day it is the
/// only part of this app anyone looks at.
enum QuotaColor {

    /// Remaining session quota in the menu bar: 60 and up green, 40–59 yellow,
    /// under 40 red.
    static func menuBar(remaining: Int) -> Color {
        switch remaining {
        case ..<40: return .red
        case ..<60: return .yellow
        default: return .green
        }
    }

    /// Remaining quota in a ring: 50 and up green, 20–49 orange, under 20 red.
    static func ring(remaining: Int) -> Color {
        switch remaining {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }
}

// MenuBarExtra renders its label as a template image, which strips any color.
// Tinting the icon into a non-template NSImage is the only way to keep it.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    // An SF Symbol rather than a bundled image: nothing to copy in build.sh, and
    // no third-party artwork to redistribute.
    private static let baseIcon: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard
            let image = NSImage(
                systemSymbolName: "asterisk",
                accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let base = Self.baseIcon {
            if let percentage = viewModel.sessionRemaining {
                Image(
                    nsImage: Self.tinted(
                        base,
                        color: QuotaColor.menuBar(remaining: percentage),
                        description: viewModel.menuBarAccessibilityText))
            } else {
                // No data yet: template rendering lets macOS pick the menu bar color.
                Image(nsImage: base)
            }
        } else {
            // Belt and braces. Every macOS this app supports ships the symbol,
            // so this shows a number rather than nothing if that ever changes.
            Text(viewModel.menuBarText)
        }
    }

    @MainActor
    private static func tinted(_ base: NSImage, color: Color, description: String) -> NSImage {
        let renderer = ImageRenderer(
            content:
                Image(nsImage: base)
                .renderingMode(.template)
                .foregroundColor(color)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? base
        image.isTemplate = false
        // The colour is the whole message here, and VoiceOver cannot see it.
        image.accessibilityDescription = description
        return image
    }
}

struct UsageDetailView: View {
    @ObservedObject var viewModel: UsageViewModel
    var strings: Strings = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .frame(maxWidth: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }

            let limits = viewModel.visibleLimits
            if !limits.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(limits.enumerated()), id: \.offset) { _, limit in
                        UsageRing(limit: limit, strings: strings)
                    }
                }
            } else if viewModel.errorMessage == nil {
                // A successful fetch that carries no limits is not "still loading".
                Text(viewModel.lastUpdated == nil ? strings.loading : strings.noWindows)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Text(strings.updated(viewModel.lastUpdatedText(strings)))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button(viewModel.isLoading ? strings.refreshing : strings.refresh) {
                    viewModel.refresh()
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r")

                Button(strings.quit) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
    }
}

struct UsageRing: View {
    let limit: UsageLimit
    var strings: Strings = .current

    private static let lineWidth: CGFloat = 6
    private static let diameter: CGFloat = 52

    var body: some View {
        // A limit with no figure never reaches here — UsageViewModel.visibleLimits
        // drops it. Drawing 0% would read as "exhausted" rather than "unknown".
        if let percentage = limit.remainingPercentage {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: Self.lineWidth)
                    Circle()
                        .trim(from: 0, to: CGFloat(percentage) / 100)
                        .stroke(
                            QuotaColor.ring(remaining: percentage),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(percentage)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                }
                .frame(width: Self.diameter, height: Self.diameter)

                Text(limit.label(strings))
                    .font(.caption)
                    .lineLimit(1)
                Text(limit.resetTimeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                strings.ringDescription(
                    window: limit.label(strings),
                    remaining: percentage,
                    resets: limit.resetTimeString))
        }
    }
}
