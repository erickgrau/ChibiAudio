#if os(iOS)
import AVKit
import SwiftUI

/// System audio route picker (AirPlay / Bluetooth / USB DAC) for Now Playing Soft PASS.
/// Keeps AVPlayer external playback as the route authority; does not force a custom session path.
/// The Mac variant below wraps the AppKit AVRoutePickerView for AirPlay; other
/// Mac outputs follow the system default chosen in Sound settings.
struct RoutePickerButton: UIViewRepresentable {
    var tint: UIColor = UIColor(ChibiTheme.amber)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = tint
        view.activeTintColor = UIColor(ChibiTheme.teal)
        // Let the intrinsic AirPlay glyph size itself; callers frame the representable.
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = UIColor(ChibiTheme.teal)
    }
}
#else
import AVKit
import SwiftUI

/// Output picker for the Mac player bar: the system AVRoutePickerView,
/// which lists AirPlay devices for the given player. Built-in, USB and
/// Bluetooth outputs still follow the system default chosen in Sound
/// settings; the app does not switch them itself.
struct RoutePickerButton: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(NSColor(ChibiTheme.textSecondary), for: .normal)
        view.setRoutePickerButtonColor(NSColor(ChibiTheme.teal), for: .active)
        view.setAccessibilityLabel("Audio Output")
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#endif
