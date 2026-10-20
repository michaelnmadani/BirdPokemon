import SwiftUI
import AVFoundation

/// A minimal, purpose-built camera screen. Uses AVFoundation so we can pick
/// the telephoto lens and zoom, which UIImagePickerController doesn't offer.
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    func makeUIViewController(context: Context) -> CameraController {
        let vc = CameraController()
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraController, context: Context) {}
}
