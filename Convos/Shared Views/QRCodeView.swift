import ConvosCore
import SwiftUI

struct QRCodeView: View {
    let identifier: String
    let backgroundColor: Color
    let foregroundColor: Color
    @State private var isRegenerating: Bool = false
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?
    @Environment(\.displayScale) private var displayScale: CGFloat

    init(identifier: String,
         backgroundColor: Color = .colorBackgroundPrimary,
         foregroundColor: Color = .colorTextPrimary) {
        self.identifier = identifier
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    private func generateQRCode() async -> UIImage? {
        let options: QRCodeGenerator.Options = QRCodeGenerator.Options(
            scale: displayScale,
            displaySize: 220,
            foregroundColor: UIColor(foregroundColor),
            backgroundColor: .clear,
        )
        return await QRCodeGenerator.generate(from: identifier, options: options)
    }

    private func updateQRCode() {
        generationTask?.cancel()

        guard !identifier.isEmpty else { return }

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
                    .fill(.colorFillMinimal)
                    .frame(width: 220, height: 220)
            }

            ShareLink(item: identifier) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24.0, weight: .medium))
                    .foregroundStyle(.colorTextPrimaryInverted)
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
            updateQRCode()
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }
}

#Preview("Automatic Colors") {
    @Previewable @State var identifier: String = UUID().uuidString

    VStack(spacing: 40.0) {
        QRCodeView(identifier: identifier)

        Button("Refresh", systemImage: "shuffle.circle.fill") {
            identifier = UUID().uuidString
        }
    }
}

#Preview("Custom Colors") {
    @Previewable @State var identifier: String = UUID().uuidString

    VStack(spacing: 40.0) {
        QRCodeView(
            identifier: identifier,
            backgroundColor: .purple,
            foregroundColor: .white
        )

        Button("Refresh", systemImage: "shuffle.circle.fill") {
            identifier = UUID().uuidString
        }
    }
}
