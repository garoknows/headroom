import WiggleroomCore
import SwiftUI

/// What a card shows: numbers, the "connect" steps, or a note that this build can't share data.
public enum CardContent: Equatable, Sendable {
    case usage(UsageDisplay)
    case empty
    /// Unsigned builds have no App Group, so the widget can't receive numbers.
    case unavailable
}

public enum CardLayout: Sendable {
    case small, medium, popover
}

/// The Wiggleroom card: used by the widget, the menu bar popover and the docs pictures.
/// It draws no background of its own, so the widget can use WidgetKit's container background.
public struct UsageCard: View {
    let content: CardContent
    let layout: CardLayout
    /// When true, the session countdown ticks by itself ("Resets in 3 hr, 12 min").
    let live: Bool
    @Environment(\.colorScheme) private var scheme

    public init(content: CardContent, layout: CardLayout, live: Bool = true) {
        self.content = content
        self.layout = layout
        self.live = live
    }

    public var body: some View {
        let p = Palette(scheme)
        Group {
            switch content {
            case .usage(let d): layout == .small ? AnyView(SmallUsage(display: d, palette: p, live: live)) : AnyView(RowsUsage(display: d, palette: p, live: live, maxRows: layout == .medium ? 2 : 6, fillHeight: layout == .medium))
            case .empty: EmptyCard(layout: layout, palette: p)
            case .unavailable: UnavailableCard(layout: layout, palette: p)
            }
        }
        .foregroundStyle(p.text)
    }
}

// MARK: Pieces

struct UsageBar: View {
    let fraction: Double
    let color: Color
    let track: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: fraction <= 0 ? 0 : max(height, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct ResetLine: View {
    let row: LimitRow
    let short: Bool
    let live: Bool

    var body: some View {
        if live, row.isSession, case .upcoming(let date) = row.reset {
            Text("Resets in \(date, style: .relative)")
        } else {
            Text(short ? row.resetTextShort : row.resetText)
        }
    }
}

struct AsOfLine: View {
    let display: UsageDisplay
    let palette: Palette
    /// "Codex · As of 2:41 PM" when the card names its tool there.
    var toolName: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if display.freshness != .fresh {
                Image(systemName: "clock.badge.exclamationmark").imageScale(.small)
            }
            Text(toolName.map { "\($0) · \(display.asOfText)" } ?? display.asOfText)
        }
        .font(.system(size: 10))
        .foregroundStyle(display.freshness == .fresh ? palette.secondary : palette.amber)
        .accessibilityLabel(display.freshness == .fresh ? display.asOfText : "\(display.asOfText). These numbers may be out of date.")
    }
}

/// One limit: name and reset time on the left, "% used" on the right, bar below.
struct LimitRowView: View {
    let row: LimitRow
    let palette: Palette
    let live: Bool
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 13, weight: .semibold))
                    ResetLine(row: row, short: false, live: live)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                Text(row.percentText)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.secondary)
            }
            UsageBar(fraction: row.usedPercent / 100, color: palette.fill(row.level), track: palette.track, height: 7)
                .opacity(dimmed ? 0.45 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title): \(row.percentText). \(row.resetText).")
    }
}

struct RowsUsage: View {
    let display: UsageDisplay
    let palette: Palette
    let live: Bool
    let maxRows: Int
    /// In the widget the "as of" line sits at the bottom; in the popover it follows the rows.
    let fillHeight: Bool
    var toolName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(display.rows.prefix(maxRows)) { row in
                LimitRowView(row: row, palette: palette, live: live, dimmed: display.freshness == .veryStale)
            }
            if fillHeight { Spacer(minLength: 0) }
            AsOfLine(display: display, palette: palette, toolName: toolName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SmallUsage: View {
    let display: UsageDisplay
    let palette: Palette
    let live: Bool
    /// Shown above the limit's name in 0.2's widgets ("Codex", then "This week").
    var toolName: String? = nil

    var body: some View {
        if let row = display.primary {
            VStack(alignment: .leading, spacing: toolName == nil ? 4 : 2) {
                if let toolName {
                    Text(toolName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(row.title).font(.system(size: 11)).foregroundStyle(palette.secondary).lineLimit(1)
                } else {
                    Text(row.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.secondary)
                }
                Group {
                    if let pct = row.percent {
                        Text("\(pct)%").font(.system(size: 36, weight: .semibold).monospacedDigit())
                    } else {
                        Text("Waiting").font(.system(size: 24, weight: .semibold))
                    }
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                UsageBar(fraction: row.usedPercent / 100, color: palette.fill(row.level), track: palette.track, height: 7)
                    .opacity(display.freshness == .veryStale ? 0.45 : 1)
                    .padding(.vertical, 2)
                ResetLine(row: row, short: true, live: live)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                AsOfLine(display: display, palette: palette)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct EmptyCard: View {
    let layout: CardLayout
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .small ? 6 : 8) {
            HStack(spacing: 8) {
                WiggleroomMark().frame(width: 22, height: 22)
                Text(layout == .small ? "Wiggleroom" : "Connect Wiggleroom to Claude Code")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }
            if layout == .small {
                Text("Connect Wiggleroom to Claude Code to see your plan usage.")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Text("Open Wiggleroom to set up").font(.system(size: 10)).foregroundStyle(palette.blue)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    step(1, "Open Wiggleroom from your Applications folder.")
                    step(2, "Click Connect to Claude Code.")
                    step(3, "Send a message in Claude Code. Your usage shows here.")
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(palette.blue)
                .frame(width: 9, alignment: .leading)
            Text(text)
        }
    }
}

struct UnavailableCard: View {
    let layout: CardLayout
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WiggleroomMark().frame(width: 22, height: 22)
                Text("Wiggleroom").font(.system(size: 13, weight: .semibold))
            }
            Text("This copy of Wiggleroom can't share numbers with widgets. Install the signed release from the Wiggleroom website.")
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
