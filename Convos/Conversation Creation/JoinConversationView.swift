import SwiftUI

struct JoinConversationView: View {
    @State private var qrScannerDelegate: QRScannerDelegate = QRScannerDelegate()
    @Environment(\.dismiss) var dismiss: DismissAction
    let onScannedCode: (String) -> Void

    init(onScannedCode: @escaping (String) -> Void) {
        self.onScannedCode = onScannedCode
    }

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
                        Spacer()

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
                            .foregroundStyle(.white.opacity(0.7))

                        Spacer()

                        Button {
                            if let code = UIPasteboard.general.string {
                                onScannedCode(code)
                            }
                        } label: {
                            Text("Or paste a link")
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextSecondary)
                                .padding(.horizontal, DesignConstants.Spacing.step4x)
                                .padding(.vertical, DesignConstants.Spacing.step3x)
                                .frame(maxWidth: .infinity)
                        }
                        .glassEffect(.regular, in: Capsule())
                        .padding(.horizontal, DesignConstants.Spacing.step6x)
                        .padding(.bottom, DesignConstants.Spacing.step6x)
                    }
                }
                .compositingGroup()
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: qrScannerDelegate.scannedCode) { _, newValue in
            if let code = newValue {
                onScannedCode(code)
            }
        }
    }

    private func handleCode(code: String) {
    }
}

#Preview {
    JoinConversationView(onScannedCode: { _ in })
}
