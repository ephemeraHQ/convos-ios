import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let identifier: String
    let backgroundColor: Color
    let foregroundColor: Color
    @State private var isRegenerating: Bool = false
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?

    init(identifier: String, backgroundColor: Color = .white, foregroundColor: Color = .black) {
        self.identifier = identifier
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.currentQRCode = ImageCache.shared.image(for: identifier)
    }

    private func generateQRCode() async -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.roundedQRCodeGenerator()

        filter.message = Data(identifier.utf8)
        filter.roundedMarkers = 1
        filter.roundedData = false
        filter.centerSpaceSize = 0.3
        filter.correctionLevel = "H"
        filter.color1 = CIColor(color: UIColor(foregroundColor))
        filter.color0 = CIColor(color: UIColor(backgroundColor))

        guard let outputImage = filter.outputImage else { return nil }

        let displaySize: CGFloat = 220 // The max size we display in the UI
        let screenScale = await MainActor.run { UIScreen.main.scale }

        let outputExtent = outputImage.extent
        let baseSize = max(outputExtent.width, outputExtent.height)

        // Scale to match the display size * screen scale (e.g., 220 * 3 = 660 pixels on 3x screens)
        let targetPixelSize = displaySize * screenScale
        let scaleFactor = targetPixelSize / baseSize

        let transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        ImageCache.shared.cacheImage(image, for: identifier)
        return image
    }

    private func updateQRCode() {
        generationTask?.cancel()

        isRegenerating = true

        generationTask = Task {
            let newQRCode = await generateQRCode()

            if !Task.isCancelled {
                await MainActor.run {
                    currentQRCode = newQRCode
                    isRegenerating = false
                }
            }
        }
    }

    var body: some View {
        ZStack {
            if let qrCodeImage = currentQRCode {
                Image(uiImage: qrCodeImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 220)
            } else {
                RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium)
                    .fill(backgroundColor)
                    .frame(width: 220, height: 220)
                    .overlay(
                        ProgressView()
                    )
            }

            ShareLink(item: identifier) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24.0, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .padding(DesignConstants.Spacing.step2x)
            }
            .opacity(currentQRCode == nil ? 0.0 : 1.0)
            .disabled(isRegenerating)
            .animation(.easeInOut(duration: 0.95), value: isRegenerating)
        }
        .animation(.easeInOut(duration: 0.95), value: isRegenerating)
        .onChange(of: identifier) { oldIdentifier, newIdentifier in
            guard oldIdentifier != newIdentifier else { return }
            updateQRCode()
        }
        .onAppear {
            if currentQRCode == nil {
                updateQRCode()
            }
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }
}

#Preview {
    @Previewable @State var identifier: String = UUID().uuidString

    VStack(spacing: 40.0) {
        QRCodeView(
            identifier: identifier,
            backgroundColor: .black,
            foregroundColor: .white
        )

        Button("Refresh", systemImage: "shuffle.circle.fill") {
            identifier = UUID().uuidString
        }
    }
}
