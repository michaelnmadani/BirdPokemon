import UIKit
import AVFoundation

/// Full-screen still camera tuned for birds: picks the best back camera
/// (so telephoto lenses are used when zooming), supports pinch zoom up to
/// 15x, and handles permission and missing-camera states.
final class CameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "DownUnderBirdCollector.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var isConfigured = false

    /// `videoZoomFactor` that corresponds to the main wide lens ("1x").
    private var wideLensFactor: CGFloat = 1
    private var maxZoomFactor: CGFloat = 1
    private var zoomAtPinchStart: CGFloat = 1
    private static let maxDisplayZoom: CGFloat = 15
    private static let quickZoomSteps: [CGFloat] = [1, 2, 5, 10]

    private let shutterButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let zoomButton = UIButton(type: .system)
    private let messageLabel = UILabel()
    private let settingsButton = UIButton(type: .system)

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        configureUI()
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
        checkPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session, weak self] in
            if self?.isConfigured == true, !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Setup

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() } else { self?.showPermissionDenied() }
                }
            }
        default:
            showPermissionDenied()
        }
    }

    private static func bestBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.first
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard
                let device = Self.bestBackCamera(),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                DispatchQueue.main.async { self.showMessage("No camera is available on this device.") }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .quality
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.session.commitConfiguration()

            // Virtual devices that include an ultra-wide start at 0.5x; the
            // first switch-over factor is where the main wide lens takes over.
            let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            let wide = hasUltraWide ? (device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1) : 1
            let maxFactor = min(device.maxAvailableVideoZoomFactor, wide * Self.maxDisplayZoom)
            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = wide
                device.unlockForConfiguration()
            }

            self.device = device
            self.wideLensFactor = wide
            self.maxZoomFactor = maxFactor
            self.isConfigured = true
            self.session.startRunning()

            DispatchQueue.main.async {
                if let connection = self.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                self.shutterButton.isEnabled = true
                self.zoomButton.isHidden = maxFactor <= wide
                self.updateZoomLabel(factor: wide)
            }
        }
    }

    private func configureUI() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.layer.borderWidth = 4
        shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        shutterButton.accessibilityLabel = "Take photo"
        shutterButton.isEnabled = false
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)
        view.addSubview(shutterButton)

        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.setTitleColor(.white, for: .normal)
        zoomButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        zoomButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        zoomButton.layer.cornerRadius = 22
        zoomButton.accessibilityLabel = "Zoom"
        zoomButton.isHidden = true
        zoomButton.addTarget(self, action: #selector(didTapZoom), for: .touchUpInside)
        view.addSubview(zoomButton)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true
        view.addSubview(messageLabel)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setTitle("Open Settings", for: .normal)
        settingsButton.isHidden = true
        settingsButton.addTarget(self, action: #selector(didTapSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),

            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            zoomButton.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -20),
            zoomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            zoomButton.heightAnchor.constraint(equalToConstant: 44),

            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            settingsButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            settingsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func showPermissionDenied() {
        showMessage("Camera access is off for Down Under Bird Collector. Turn it on in Settings to photograph birds, or pick a photo from your library instead.")
        settingsButton.isHidden = false
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.isHidden = false
        shutterButton.isHidden = true
        zoomButton.isHidden = true
    }

    // MARK: - Zoom

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device else { return }
        switch gesture.state {
        case .began:
            zoomAtPinchStart = device.videoZoomFactor
        case .changed:
            setZoom(zoomAtPinchStart * gesture.scale)
        default:
            break
        }
    }

    @objc private func didTapZoom() {
        guard let device else { return }
        let current = device.videoZoomFactor / wideLensFactor
        let next = Self.quickZoomSteps.first { $0 > current + 0.05 && $0 * wideLensFactor <= maxZoomFactor } ?? 1
        setZoom(next * wideLensFactor)
    }

    private func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor, min(factor, maxZoomFactor))
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
        updateZoomLabel(factor: clamped)
    }

    private func updateZoomLabel(factor: CGFloat) {
        let display = factor / wideLensFactor
        let text = display < 10 ? String(format: "%.1fx", display) : String(format: "%.0fx", display)
        zoomButton.setTitle(text.replacingOccurrences(of: ".0x", with: "x"), for: .normal)
    }

    // MARK: - Capture

    @objc private func didTapShutter() {
        shutterButton.isEnabled = false
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func didTapCancel() {
        onCancel?()
    }

    @objc private func didTapSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shutterButton.isEnabled = true
            if let image {
                self.onCapture?(image)
            }
        }
    }
}
