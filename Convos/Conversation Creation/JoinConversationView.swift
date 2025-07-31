import SwiftUI

struct JoinConversationView: View {
    @Bindable var newConversationState: NewConversationState
    let showsToolbar: Bool
    @StateObject private var qrScannerDelegate: QRScannerDelegate = QRScannerDelegate()
    @Environment(\.dismiss) var dismiss: DismissAction
    let onScannedCode: () -> Void

    init(
        newConversationState: NewConversationState,
        showsToolbar: Bool,
        onScannedCode: @escaping () -> Void = {}
    ) {
        self.newConversationState = newConversationState
        self.showsToolbar = showsToolbar
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
                                if handleCode(code: code) {
                                    dismiss()
                                }
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
                    }
                    .padding(.bottom, 100.0)
                }
                .compositingGroup()
            }
            .ignoresSafeArea()
            .toolbar {
                if showsToolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: qrScannerDelegate.scannedCode) { _, newValue in
            if let code = newValue {
                if handleCode(code: code) {
                    dismiss()
                }
            }
        }
    }

    @discardableResult
    private func handleCode(code: String) -> Bool {
        guard let result = Invite.parse(temporaryInviteString: code) else {
            return false
        }
        Logger.info("Scanned code: \(result)")
        newConversationState.joinConversation(inboxId: result.inboxId, inviteCode: result.code)
        onScannedCode()
        return true
    }
}

#Preview {
    JoinConversationView(newConversationState: .init(session: MockInboxesService()), showsToolbar: true)
}
