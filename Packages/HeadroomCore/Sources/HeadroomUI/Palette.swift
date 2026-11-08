import HeadroomCore
import SwiftUI

/// Headroom's colors (PRD section 5): a dark card like Claude's usage panel, or a white one in
/// light mode, with a blue bar that turns amber at 75% and red at 90%.
public struct Palette: Sendable {
    public let card: Color
    public let text: Color
    public let secondary: Color
    public let track: Color
    public let blue = Color(hex: 0x3B82F6)
    public let amber = Color(hex: 0xF59E0B)
    public let red = Color(hex: 0xEF4444)

    public init(_ scheme: ColorScheme) {
        if scheme == .dark {
            card = Color(hex: 0x1F1F1F); text = Color(hex: 0xECECEC); secondary = Color(hex: 0x9A9A9A); track = Color(hex: 0x2E3440)
        } else {
            card = .white; text = Color(hex: 0x1F1F1F); secondary = Color(hex: 0x6B6B6B); track = Color(hex: 0xE3E6EC)
        }
    }

    public func fill(_ level: UsageLevel) -> Color {
        switch level {
        case .normal: blue
        case .warning: amber
        case .critical: red
        }
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
