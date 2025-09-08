import ConvosCore
import SwiftUI

struct QRCodeView: View {
    let url: URL
    let backgroundColor: Color
    let foregroundColor: Color
    let centerImage: Image?
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?
    @Environment(\.displayScale) private var displayScale: CGFloat
    private let displaySize: CGFloat = 220.0

    init(url: URL,
         backgroundColor: Color = .colorBackgroundPrimary,
         foregroundColor: Color = .colorTextPrimary,
         centerImage: Image? = nil) {
        self.url = url
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.centerImage = centerImage
    }

    private func generateQRCode() async -> UIImage? {
        let options: QRCodeGenerator.Options = QRCodeGenerator.Options(
            scale: displayScale,
            displaySize: displaySize,
            foregroundColor: UIColor(foregroundColor),
            backgroundColor: UIColor(backgroundColor),
        )
        return await QRCodeGenerator.generate(from: url.absoluteString, options: options)
    }

    var background: some View {
        Group {
            if let qrCodeImage = currentQRCode {
                Image(uiImage: qrCodeImage)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fit)
            } else {
                EmptyView()
            }
        }
    }

    var overlay: some View {
        Group {
            if currentQRCode == nil {
                EmptyView()
            } else {
                ZStack {
                    if let centerImage {
                        ZStack {
                            Rectangle()
                                .fill(foregroundColor)
                            centerImage
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .frame(width: 50.0, height: 50.0)
                        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.small))
                    } else {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24.0, weight: .medium))
                                .foregroundStyle(foregroundColor)
                                .frame(width: 50, height: 50)
                                .padding(DesignConstants.Spacing.step2x)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: displaySize, height: displaySize)
            .background(background)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(backgroundColor)
                    .frame(width: 55.0, height: 55.0)

                overlay
            }
            .transition(.opacity)
            .animation(.default, value: currentQRCode)
            .task(id: url) {
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

// swiftlint:disable force_unwrapping

#Preview("Automatic Colors") {
    @Previewable @State var url: URL = URL(string: "https://local.convos.org/join/12346")!

    VStack(spacing: 40.0) {
        QRCodeView(url: url, centerImage: Image("convosIcon"))
    }
}

// swiftlint:enable force_unwrapping
