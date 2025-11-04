import AVFoundation
import ConvosCore
import SwiftUI

// MARK: - QR Scanner Delegate
@MainActor
@Observable
class QRScannerViewModel: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var scannedCode: String?
    fileprivate(set) var cameraAuthorized: Bool = false
    fileprivate(set) var cameraSetupCompleted: Bool = false
    fileprivate(set) var onSetupCamera: (() -> Void)?
    var isScanningEnabled: Bool = true
    var showInvalidInviteCodeFormat: Bool = false
    var invalidInviteCode: String?
    var presentingInvalidInviteSheet: Bool = false

    // Minimum time to wait before allowing another scan (in seconds)
    private let minimumScanInterval: TimeInterval = 3.0
    private var lastScanTime: Date?

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { @MainActor [weak self] granted in
            self?.cameraAuthorized = granted
            if granted {
                // Trigger camera setup using the callback
                self?.onSetupCamera?()
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Only process if scanning is enabled and we're not showing an error
        guard isScanningEnabled else { return }

        guard !presentingInvalidInviteSheet else { return }

        // Check if enough time has passed since the last scan
        let now = Date()
        if let lastScan = lastScanTime {
            let timeSinceLastScan = now.timeIntervalSince(lastScan)
            guard timeSinceLastScan >= minimumScanInterval else { return }
        }

        lastScanTime = now

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            scannedCode = stringValue

            // Disable further scanning after detecting a code
            isScanningEnabled = false
        }
    }

    func resetScanning() {
        isScanningEnabled = true
        scannedCode = nil
        // Note: we intentionally do NOT reset lastScanTime here
        // to maintain the minimum interval even across resets
    }

    func resetScanTimer() {
        lastScanTime = nil
    }
}

// MARK: - Camera Preview
struct QRScannerView: UIViewRepresentable {
    let viewModel: QRScannerViewModel
    @Binding var coordinator: Coordinator?

    class Coordinator {
        var orientationObserver: Any?
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var captureDevice: AVCaptureDevice?
        var parentView: UIView?

        deinit {
            // Failsafe cleanup in case dismantleUIView wasn't called
            if let captureSession = captureSession, captureSession.isRunning {
                captureSession.stopRunning()

                // Clear metadata output delegates
                captureSession.outputs.forEach { output in
                    if let metadataOutput = output as? AVCaptureMetadataOutput {
                        metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
                    }
                }
            }

            if let observer = orientationObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            previewLayer?.removeFromSuperlayer()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.parentView = view
        coordinator = context.coordinator

        viewModel.onSetupCamera = {
            self.setupCamera()
        }

        checkCameraAuthorization { @MainActor [weak viewModel] authorized in
            viewModel?.cameraAuthorized = authorized
            if authorized {
                self.setupCamera()
            }
        }

        return view
    }

    func setupCamera() {
        guard let coordinator = coordinator else { return }
        guard let view = coordinator.parentView else { return }
        setupCamera(on: view, coordinator: coordinator)
    }

    private func checkCameraAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .denied, .restricted, .notDetermined:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func setupCamera(on view: UIView, coordinator: Coordinator) {
        // Guard against duplicate initialization
        guard coordinator.captureSession == nil else {
            // If session already exists, just ensure it's running
            if let existingSession = coordinator.captureSession, !existingSession.isRunning {
                DispatchQueue.global(qos: .background).async {
                    existingSession.startRunning()
                }
            }
            return
        }

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            Logger.info("Failed to get video capture device")
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            Logger.info("Failed to create video input: \(error)")
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            Logger.info("Cannot add video input")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(viewModel, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            Logger.info("Cannot add metadata output")
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        // Use window bounds to fill entire screen including safe areas
        if let window = view.window {
            previewLayer.frame = window.bounds
        } else {
            previewLayer.frame = view.bounds
        }
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Set initial orientation
        updateVideoOrientation(for: previewLayer)

        // Store references in coordinator
        coordinator.captureSession = captureSession
        coordinator.previewLayer = previewLayer
        coordinator.captureDevice = videoCaptureDevice

        // Register for orientation notifications
        coordinator.orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Delay slightly to ensure view bounds are updated after rotation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                // Use window bounds to fill entire screen including safe areas
                if let window = view.window {
                    previewLayer.frame = view.convert(window.bounds, from: window)
                } else {
                    previewLayer.frame = view.bounds
                }
                CATransaction.commit()
                self.updateVideoOrientation(for: previewLayer)
            }
        }

        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }

        // Mark camera setup as completed
        viewModel.cameraSetupCompleted = true
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                // Use window bounds to fill entire screen including safe areas
                if let window = uiView.window {
                    previewLayer.frame = uiView.convert(window.bounds, from: window)
                } else {
                    previewLayer.frame = uiView.bounds
                }
                CATransaction.commit()
                self.updateVideoOrientation(for: previewLayer)
            }
        }
    }

    private func updateVideoOrientation(for previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection else { return }

        let orientation = UIDevice.current.orientation

        // Map device orientation to video rotation angle
        // Note: Camera sensor is mounted in landscape, so portrait needs 90° rotation
        let rotationAngle: CGFloat

        switch orientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            // Device rotated left (home button on right)
            rotationAngle = 0
        case .landscapeRight:
            // Device rotated right (home button on left)
            rotationAngle = 180
        default:
            // For face up, face down, and unknown, try to use the interface orientation
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.effectiveGeometry.interfaceOrientation {
                case .portrait:
                    rotationAngle = 90
                case .portraitUpsideDown:
                    rotationAngle = 270
                case .landscapeLeft:
                    rotationAngle = 180
                case .landscapeRight:
                    rotationAngle = 0
                default:
                    rotationAngle = 90
                }
            } else {
                rotationAngle = 90
            }
        }

        connection.videoRotationAngle = rotationAngle
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Stop the capture session immediately
        if let captureSession = coordinator.captureSession {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }

            // Remove all inputs and outputs
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { output in
                // Clear the delegate before removing the output
                if let metadataOutput = output as? AVCaptureMetadataOutput {
                    metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
                }
                captureSession.removeOutput(output)
            }
        }

        // Remove preview layer
        coordinator.previewLayer?.removeFromSuperlayer()
        coordinator.previewLayer = nil

        // Clear all references
        coordinator.captureSession = nil
        coordinator.captureDevice = nil

        // Remove orientation observer
        if let observer = coordinator.orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.orientationObserver = nil
        }
    }
}
