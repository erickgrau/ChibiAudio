import AVKit
import SwiftUI

/// System audio route picker (AirPlay / Bluetooth / USB DAC) for Now Playing Soft PASS.
/// Keeps AVPlayer external playback as the route authority; does not force a custom session path.
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
