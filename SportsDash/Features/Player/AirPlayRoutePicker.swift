import AVKit
import SwiftUI

#if canImport(UIKit)
import UIKit

/// System AirPlay / external playback route picker (iOS).
struct AirPlayRoutePicker: UIViewRepresentable {
    var tint: UIColor = .white
    var activeTint: UIColor = UIColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1) // gold-ish

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tint
        picker.activeTintColor = activeTint
        picker.prioritizesVideoDevices = true
        #if os(iOS)
        picker.backgroundColor = .clear
        #endif
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = activeTint
    }
}
#endif
