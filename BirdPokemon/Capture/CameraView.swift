import SwiftUI
import AVFoundation

/// A minimal, purpose-built camera screen. Uses AVFoundation so we can
/// capture a high-quality still without going through the full UIImagePicker
/// (which doesn't offer SwiftUI-native orientation handling).
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraController {
        let vc = CameraController()
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraController, context: Context) {}
}
