import SwiftUI

/// Collects the real laid-out frames of marked parts of a window, in window coordinates.
/// The layout tests and the docs renders put one in the environment; the app never does, so
/// in the app the probes do nothing.
@MainActor
public final class LayoutRecorder {
    public private(set) var frames: [String: CGRect] = [:]
    public init() {}
    func record(_ name: String, _ frame: CGRect) { frames[name] = frame }
}

private struct LayoutRecorderKey: EnvironmentKey {
    static let defaultValue: LayoutRecorder? = nil
}

extension EnvironmentValues {
    public var layoutRecorder: LayoutRecorder? {
        get { self[LayoutRecorderKey.self] }
        set { self[LayoutRecorderKey.self] = newValue }
    }
}

struct LayoutProbe: ViewModifier {
    let name: String?
    @Environment(\.layoutRecorder) private var recorder

    func body(content: Content) -> some View {
        if let recorder, let name {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { recorder.record(name, $0) }
        } else {
            content
        }
    }
}

extension View {
    /// Reports this view's laid-out frame (its layout size, not its drawn size) to the
    /// layout recorder, if there is one.
    func layoutProbe(_ name: String?) -> some View { modifier(LayoutProbe(name: name)) }
}
