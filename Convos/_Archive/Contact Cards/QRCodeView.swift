import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    @Binding var identifier: String
    let backgroundColor: Color
    let foregroundColor: Color
    @State private var isRegenerating: Bool = false
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?

    init(identifier: Binding<String>, backgroundColor: Color = .white, foregroundColor: Color = .black) {
        self._identifier = identifier
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
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

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
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
            }

            ShareLink(item: identifier) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24.0, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 50, height: 50)
                    .padding(DesignConstants.Spacing.step2x)
            }
            .background(backgroundColor)
            .disabled(isRegenerating)
            .opacity(isRegenerating ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.95), value: isRegenerating)
        }
        .blur(radius: isRegenerating ? 15.0 : 0)
        .animation(.easeInOut(duration: 0.95), value: isRegenerating)
        .onChange(of: identifier) { oldIdentifier, newIdentifier in
            guard oldIdentifier != newIdentifier else { return }
            updateQRCode()
        }
        .onAppear {
            updateQRCode()
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }
}

#Preview {
    @Previewable @State var identifier: String = UUID().uuidString

    VStack(spacing: 40.0) {
        QRCodeView(identifier: $identifier, backgroundColor: .black, foregroundColor: .white)

        Button("Refresh", systemImage: "shuffle.circle.fill") {
            identifier = UUID().uuidString
        }
    }
}
