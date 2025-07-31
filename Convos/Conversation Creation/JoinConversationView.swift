import SwiftUI

struct JoinConversationView: View {
    let newConversationState: NewConversationState
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
                    }
                    .padding(.bottom, 100.0)
                }
                .compositingGroup()
            }
            .ignoresSafeArea()
            .toolbar {
                if showsToolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: qrScannerDelegate.scannedCode) { _, newValue in
            if let code = newValue {
                guard let result = Invite.parse(temporaryInviteString: code) else {
                    Logger.error("Failed to parse invite code: '\(code)'")
                    return
                }

                Logger.info("Joining conversation with inboxId: '\(result.inboxId)', code: '\(result.code)'")
                newConversationState.joinConversation(inboxId: result.inboxId, inviteCode: result.code)
                onScannedCode()
            }
        }
    }
}

#Preview {
    JoinConversationView(newConversationState: .init(session: MockInboxesService()), showsToolbar: true)
}
