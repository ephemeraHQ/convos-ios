import ConvosCore
import SwiftUI

struct QRCodeView: View {
    let identifier: String
    let backgroundColor: Color?
    let foregroundColor: Color?
    @State private var isRegenerating: Bool = false
    @State private var currentQRCode: UIImage?
    @State private var generationTask: Task<Void, Never>?
    @Environment(\.displayScale) private var displayScale: CGFloat
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    /// Initialize with automatic light/dark mode support
    init(identifier: String) {
        self.identifier = identifier
        self.backgroundColor = nil
        self.foregroundColor = nil
    }

    /// Initialize with custom colors
    init(identifier: String, backgroundColor: Color, foregroundColor: Color) {
        self.identifier = identifier
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    private func generateQRCode() async -> UIImage? {
        let options: QRCodeGenerator.Options

        if let backgroundColor = backgroundColor, let foregroundColor = foregroundColor {
            // Use custom colors
            options = QRCodeGenerator.Options(
                scale: displayScale,
                displaySize: 220,
                foregroundColor: UIColor(foregroundColor),
                backgroundColor: UIColor(backgroundColor)
            )
        } else {
            // Use appropriate preset based on color scheme
            options = colorScheme == .dark ? .qrCodeDark : .qrCodeLight
        }

        return await QRCodeGenerator.generate(from: identifier, options: options)
    }

    private var effectiveBackgroundColor: Color {
        if let backgroundColor = backgroundColor {
            return backgroundColor
        }
        return colorScheme == .dark ? .black : .white
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
        .onChange(of: colorScheme) { _, _ in
            // Regenerate QR code when color scheme changes (if using automatic colors)
            if backgroundColor == nil && foregroundColor == nil {
                updateQRCode()
            }
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
