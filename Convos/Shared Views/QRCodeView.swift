import ConvosCore
import SwiftUI

struct QRCodeView: View {
    let identifier: String
    let backgroundColor: Color
    let foregroundColor: Color
    let centerImage: Image?
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?
    @Environment(\.displayScale) private var displayScale: CGFloat

    init(identifier: String,
         backgroundColor: Color = .colorBackgroundPrimary,
         foregroundColor: Color = .colorTextPrimary,
         centerImage: Image? = nil) {
        self.identifier = identifier
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.centerImage = centerImage
    }

    private func generateQRCode() async -> UIImage? {
        let options: QRCodeGenerator.Options = QRCodeGenerator.Options(
            scale: displayScale,
            displaySize: 220,
            foregroundColor: UIColor(foregroundColor),
            backgroundColor: UIColor(backgroundColor),
        )
        return await QRCodeGenerator.generate(from: identifier, options: options)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .frame(width: 220, height: 220)

            if let qrCodeImage = currentQRCode {
                Image(uiImage: qrCodeImage)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 220)
            }

            // removes center rounded rect
            Rectangle()
                .fill(backgroundColor)
                .frame(width: 55.0, height: 55.0)

            if let centerImage {
                ZStack {
                    Rectangle()
                        .fill(foregroundColor)

                    centerImage
                        .resizable()
                }
                .frame(width: 50.0, height: 50.0)
                .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.small))
            } else {
                ShareLink(item: identifier) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 24.0, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(width: 50, height: 50)
                        .padding(DesignConstants.Spacing.step2x)
                }
                .opacity(currentQRCode == nil ? 0.0 : 1.0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentQRCode)
        .task {
            let newQRCode = await generateQRCode()

            if !Task.isCancelled {
                await MainActor.run {
                    currentQRCode = newQRCode
                }
            }
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }
}

#Preview("Automatic Colors") {
    @Previewable @State var identifier: String = UUID().uuidString

    VStack(spacing: 40.0) {
        QRCodeView(identifier: identifier, centerImage: Image("convosIcon"))

        Button("Refresh", systemImage: "shuffle.circle.fill") {
            identifier = UUID().uuidString
        }
    }
}
