import AVFoundation
import SwiftUI

struct JoinConversationView: View {
    @StateObject private var qrScannerDelegate: QRScannerDelegate = QRScannerDelegate()
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView(delegate: qrScannerDelegate)
                    .ignoresSafeArea()

                let cutoutSize = 240.0
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()

                    VStack(spacing: DesignConstants.Spacing.stepX) {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: cutoutSize, height: cutoutSize)
                            .blendMode(.destinationOut)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white, lineWidth: 4)
                                    .frame(width: cutoutSize, height: cutoutSize)
                            )
                            .padding(.bottom, DesignConstants.Spacing.step3x)
                        Text("Scan a Convo Code")
                            .font(.system(size: 16.0))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text("You’ll join immediately and anonymously")
                            .font(.system(size: 12.0))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 100.0)
                }
                .compositingGroup()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: qrScannerDelegate.scannedCode) { _, newValue in
            if let code = newValue {
                Logger.info("Scanned code: \(code)")
            }
        }
    }
}

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
            print("Failed to get video capture device")
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            print("Failed to create video input: \(error)")
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            print("Cannot add video input")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            print("Cannot add metadata output")
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Store references for update
        view.layer.setValue(captureSession, forKey: "captureSession")
        view.layer.setValue(previewLayer, forKey: "previewLayer")
        view.layer.setValue(videoCaptureDevice, forKey: "captureDevice")

        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame
        if let previewLayer = uiView.layer.value(forKey: "previewLayer") as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        if let captureSession = uiView.layer.value(forKey: "captureSession") as? AVCaptureSession {
            captureSession.stopRunning()
        }
    }
}

#Preview {
    JoinConversationView()
}
