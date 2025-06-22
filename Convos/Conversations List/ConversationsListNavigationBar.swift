import SwiftUI

struct ConversationsListNavigationBar: View {
    @Binding var selectedInbox: Inbox?
    let inboxes: [Inbox]

    let onCompose: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 0.0) {
            HStack(spacing: DesignConstants.Spacing.step4x) {
                HStack(spacing: DesignConstants.Spacing.step2x) {
                    if let selectedInbox {
                        ProfileAvatarView(profile: selectedInbox.profile)
                            .frame(maxHeight: 24.0)

                        Text(selectedInbox.profile.name)
                            .font(.system(size: 16.0, weight: .regular))
                            .foregroundColor(.colorTextPrimary)
                            .padding(.vertical, 10.0)
                    } else {
                        MonogramView()
                            .frame(maxHeight: 24.0)

                        Text("Convos")
                            .font(.system(size: 16.0, weight: .regular))
                            .foregroundColor(.colorTextPrimary)
                            .padding(.vertical, 10.0)
                    }
                }
                .padding(.horizontal, DesignConstants.Spacing.step2x)
                .contextMenu {
                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Spacer()

                HStack {
                    Button {
                        onCompose()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 24.0))
                            .padding(.bottom, 4.0) // vertical align based on square
                    }
                }
                .foregroundColor(.colorTextPrimary)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
            .padding(DesignConstants.Spacing.step4x)
        }
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    @Previewable @State var selectedInbox: Inbox? = nil
    @Previewable @State var inboxes: [Inbox] = []

    ConversationsListNavigationBar(
        selectedInbox: $selectedInbox,
        inboxes: inboxes,
        onCompose: {},
        onSignOut: {}
    )
}
