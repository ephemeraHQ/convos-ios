import AVFoundation
import SwiftUI

// MARK: - QR Scanner Delegate
class QRScannerDelegate: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            scannedCode = stringValue
        }
    }
}

// MARK: - Camera Preview
struct QRScannerView: UIViewRepresentable {
    let delegate: QRScannerDelegate

    class Coordinator {
        var orientationObserver: Any?
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var captureDevice: AVCaptureDevice?

        deinit {
            if let observer = orientationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            captureSession?.stopRunning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Check camera authorization
        checkCameraAuthorization { authorized in
            if authorized {
                DispatchQueue.main.async {
                    self.setupCamera(on: view, coordinator: context.coordinator)
                }
            }
        }

        return view
    }

    private func checkCameraAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func setupCamera(on view: UIView, coordinator: Coordinator) {
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

            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
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
        // All cleanup is handled in Coordinator's deinit
    }
}
