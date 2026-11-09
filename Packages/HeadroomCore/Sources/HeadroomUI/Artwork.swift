import HeadroomCore
import SwiftUI

/// The Headroom mark: a dark rounded square holding a tall bar, filled about halfway in blue,
/// with a light "ceiling" line above it. The empty space between fill and ceiling is the headroom.
/// One drawing for the app icon, the setup window, the widget's empty state and the site icon
/// (site/icon.svg uses the same numbers on a 1024 grid).
public struct HeadroomMark: View {
    /// True for the app icon: the tile sits on Apple's macOS icon grid (824 of 1024, centered).
    var iconGrid: Bool

    public init(iconGrid: Bool = false) { self.iconGrid = iconGrid }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let unit = s / 1024
            // Without the icon grid, the tile fills the whole frame.
            let scale = iconGrid ? unit : s / 824
            // Coordinates below are on the 1024 grid; without the icon grid, shift so the tile starts at 0.
            let origin = iconGrid ? 0 : -100 * scale
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 185.4 * scale, style: .continuous)
                    .fill(Color(hex: 0x1F1F1F))
                    .frame(width: 824 * scale, height: 824 * scale)
                    .offset(x: origin + 100 * scale, y: origin + 100 * scale)
                    .shadow(color: .black.opacity(iconGrid ? 0.3 : 0), radius: 10 * unit, y: 6 * unit)
                Capsule()
                    .fill(Color(hex: 0xECECEC))
                    .frame(width: 440 * scale, height: 22 * scale)
                    .offset(x: origin + 292 * scale, y: origin + 214 * scale)
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0x2E3440))
                    Rectangle().fill(Color(hex: 0x3B82F6)).frame(height: 274 * scale)
                }
                .frame(width: 320 * scale, height: 520 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 64 * scale, style: .continuous))
                .offset(x: origin + 352 * scale, y: origin + 282 * scale)
            }
            .frame(width: s, height: s, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Invented numbers for previews, pictures and the widget gallery. Never real data.
public enum SampleData {
    /// "Current session 23%, resets in 3 hr 12 min; this week 41%, resets Monday 1:00 AM",
    /// relative to `now` in `timeZone`.
    public static func snapshot(now: Date, timeZone: TimeZone = .autoupdatingCurrent,
                                session: Double = 23, week: Double = 41, age: TimeInterval = 0) -> UsageSnapshot {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        // Next Monday 1:00 AM (local), at least a day away.
        var monday = cal.nextDate(after: now.addingTimeInterval(86400), matching: DateComponents(hour: 1, minute: 0, weekday: 2),
                                  matchingPolicy: .nextTime) ?? now.addingTimeInterval(4 * 86400)
        if monday.timeIntervalSince(now) > 7 * 86400 { monday.addTimeInterval(-7 * 86400) }
        return UsageSnapshot(updatedAt: now.addingTimeInterval(-age), limits: [
            LimitWindow(id: LimitKind.session, usedPercent: session, resetsAt: now.addingTimeInterval(3 * 3600 + 12 * 60)),
            LimitWindow(id: LimitKind.weekly, usedPercent: week, resetsAt: monday),
        ])
    }
}
