import SwiftUI

/// Draws a fixed-size picture at the width it's offered: full size if there's room, otherwise
/// scaled down. Unlike `scaleEffect` alone, the layout size shrinks too, so the picture can
/// never make its container wider than the window (0.1.0's setup window was cut off that way).
public struct FitToWidth<Content: View>: View {
    let size: CGSize
    let probe: String?
    let content: Content

    /// `probe` names the picture for the layout tests: "<probe>" is its layout frame and
    /// "<probe> drawn" is where it is actually drawn after scaling.
    public init(_ size: CGSize, probe: String? = nil, @ViewBuilder content: () -> Content) {
        self.size = size
        self.probe = probe
        self.content = content()
    }

    public var body: some View {
        Color.clear
            .frame(maxWidth: size.width)
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    content
                        .frame(width: size.width, height: size.height)
                        .layoutProbe(probe.map { "\($0) drawn" })
                        .scaleEffect(min(1, geo.size.width / size.width), anchor: .topLeading)
                }
            }
            .layoutProbe(probe)
    }
}
