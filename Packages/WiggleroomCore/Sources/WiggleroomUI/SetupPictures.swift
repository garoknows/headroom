import WiggleroomCore
import SwiftUI

// Drawings that show how to add the Wiggleroom widget to Notification Center, with red boxes and
// numbered markers. They are drawn, not screenshots (Keymend D14): they follow light and dark
// mode, never show anyone's real desktop, and the docs pictures are rendered from the same views.

/// A red numbered circle.
public struct StepMarker: View {
    let number: Int
    public init(_ number: Int) { self.number = number }
    public var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(hex: 0xEF4444)))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .accessibilityLabel("Step \(number)")
    }
}

/// A red box around something, with its numbered marker at one corner (top left by default).
struct Callout: ViewModifier {
    let number: Int
    let corner: Alignment
    func body(content: Content) -> some View {
        content
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color(hex: 0xEF4444), lineWidth: 2.5))
            .overlay(alignment: corner) {
                StepMarker(number).offset(x: corner == .leading ? -30 : -14,
                                          y: corner == .bottomLeading ? 14 : (corner == .leading ? 0 : -14))
            }
    }
}

extension View {
    func callout(_ n: Int, corner: Alignment = .topLeading) -> some View { modifier(Callout(number: n, corner: corner)) }
}

/// Colors for the pretend macOS screens.
struct ScreenColors {
    let desktop: LinearGradient
    let bar: Color
    let barText: Color
    let panel: Color
    let tile: Color
    let text: Color
    let secondary: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            desktop = LinearGradient(colors: [Color(hex: 0x2B3A55), Color(hex: 0x1C2333)], startPoint: .topLeading, endPoint: .bottomTrailing)
            bar = Color.black.opacity(0.35); barText = .white
            panel = Color(hex: 0x2A2A2C).opacity(0.92); tile = Color(hex: 0x3A3A3C); text = .white; secondary = Color(hex: 0xA0A0A5)
        } else {
            desktop = LinearGradient(colors: [Color(hex: 0x9CC3F0), Color(hex: 0xD9E6F7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            bar = Color.white.opacity(0.45); barText = .black
            panel = Color(hex: 0xF2F2F4).opacity(0.95); tile = .white; text = .black; secondary = Color(hex: 0x6E6E73)
        }
    }
}

/// Picture 1: click the date and time at the right end of the menu bar.
public struct MenuBarPicture: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        let c = ScreenColors(scheme)
        ZStack(alignment: .top) {
            Rectangle().fill(c.desktop)
            HStack(spacing: 14) {
                Image(systemName: "apple.logo").font(.system(size: 13))
                Text("Finder").font(.system(size: 13, weight: .semibold))
                Text("File").font(.system(size: 13))
                Text("Edit").font(.system(size: 13))
                Spacer()
                Image(systemName: "wifi").font(.system(size: 12))
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Image(systemName: "switch.2").font(.system(size: 12))
                Text("Mon Jan 18  9:41 AM").font(.system(size: 13)).callout(1, corner: .bottomLeading)
            }
            .foregroundStyle(c.barText)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(c.bar)
        }
        .frame(width: 520, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The menu bar, with the date and time at its right end marked as step 1.")
    }
}

/// Picture 2: at the bottom of Notification Center, click Edit Widgets.
public struct NotificationCenterPicture: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        let c = ScreenColors(scheme)
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(c.desktop)
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.tile).frame(height: 70)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.tile)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.tile)
                }
                .frame(height: 92)
                Text("Edit Widgets")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.text)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(c.tile))
                    .callout(2)
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(width: 230)
            .padding(.top, 14).padding(.trailing, 14)
        }
        .frame(width: 520, height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notification Center, with the Edit Widgets button at the bottom marked as step 2.")
    }
}

/// Picture 3: search for Wiggleroom in the widget gallery, then click the + on the size you want.
public struct WidgetGalleryPicture: View {
    @Environment(\.colorScheme) private var scheme
    let sample: UsageDisplay
    public init(sample: UsageDisplay) { self.sample = sample }

    public var body: some View {
        let c = ScreenColors(scheme)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                    Text("Wiggleroom").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(c.text)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(c.tile))
                .callout(3)
                HStack(spacing: 8) {
                    WiggleroomMark().frame(width: 18, height: 18)
                    Text("Wiggleroom").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.text)
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)))
                Spacer()
            }
            .padding(16)
            .frame(width: 170)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 10) {
                Text("Wiggleroom").font(.system(size: 15, weight: .bold)).foregroundStyle(c.text)
                Text("How much of your Claude plan you've used this week, and when it resets.").font(.system(size: 11)).foregroundStyle(c.secondary)
                    .padding(.bottom, 10)
                HStack(alignment: .top, spacing: 30) {
                    preview(.small, width: 150, height: 150, plus: false)
                    preview(.medium, width: 300, height: 150, plus: true)
                }
            }
            .padding(18)
        }
        .frame(width: 700, height: 270)
        .background(c.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The widget gallery. Step 3 is the search field with Wiggleroom typed in. Step 4 is the plus button on the Wiggleroom widget.")
    }

    func preview(_ layout: CardLayout, width: CGFloat, height: CGFloat, plus: Bool) -> some View {
        UsageCard(content: .usage(sample), layout: layout, live: false)
            .padding(14)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette(scheme).card))
            .overlay(alignment: .topLeading) {
                if plus {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(hex: 0x34C759))
                        .font(.system(size: 22))
                        .callout(4, corner: .leading)
                        .offset(x: -16, y: -16)
                }
            }
    }
}
