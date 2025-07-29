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

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        // Check camera authorization
        checkCameraAuthorization { authorized in
            if authorized {
                DispatchQueue.main.async {
                    self.setupCamera(on: view)
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

    private func setupCamera(on view: UIView) {
        let captureSession = AVCaptureSession()

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
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Set initial orientation
        updateVideoOrientation(for: previewLayer)

        view.layer.setValue(captureSession, forKey: "captureSession")
        view.layer.setValue(previewLayer, forKey: "previewLayer")
        view.layer.setValue(videoCaptureDevice, forKey: "captureDevice")

        // Register for orientation notifications
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.updateVideoOrientation(for: previewLayer)
        }

        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame
        if let previewLayer = uiView.layer.value(forKey: "previewLayer") as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
            updateVideoOrientation(for: previewLayer)
        }
    }

    private func updateVideoOrientation(for previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection else { return }

        let orientation = UIDevice.current.orientation

        switch orientation {
        case .portrait:
            connection.videoOrientation = .portrait
        case .portraitUpsideDown:
            connection.videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            connection.videoOrientation = .landscapeRight
        case .landscapeRight:
            connection.videoOrientation = .landscapeLeft
        default:
            // For face up, face down, and unknown, try to use the interface orientation
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeLeft
                case .landscapeRight:
                    connection.videoOrientation = .landscapeRight
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        if let captureSession = uiView.layer.value(forKey: "captureSession") as? AVCaptureSession {
            captureSession.stopRunning()
        }

        // Remove orientation observer
        NotificationCenter.default.removeObserver(
            uiView,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
}
