import SwiftUI

@Observable
class ConversationComposerViewModel {
    var searchText: String = ""

    var conversationResults: [Conversation] = [
        .mock(),
        .mock(),
    ]

    var profileResults: [Profile] = [
        .mock(),
        .mock(),
        .mock()
    ]
}

struct ConversationComposerView: View {
    @State private var selectedProfile: Profile?
    @State private var viewModel: ConversationComposerViewModel = .init()

    private let headerHeight: CGFloat = 72.0

    var body: some View {
        VStack(spacing: 0.0) {
            // navigation bar
            Group {
                HStack(spacing: DesignConstants.Spacing.stepHalf) {
                    Button {
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24.0))
                            .foregroundColor(.colorTextPrimary)
                            .padding(.horizontal, DesignConstants.Spacing.step2x)
                            .padding(.vertical, 10.0)
                    }

                    Text("New chat")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)

                    Spacer()
                }
                .padding(DesignConstants.Spacing.step4x)
            }
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color.colorBorderSubtle2),
                alignment: .bottom
            )

            // profile search header
            HStack(alignment: .top,
                   spacing: DesignConstants.Spacing.step2x) {
                Text("To")
                    .font(.system(size: 14.0))
                    .foregroundStyle(.colorTextSecondary)
                    .frame(height: headerHeight)

                ConversationComposerProfilesField(searchText: $viewModel.searchText,
                                                  selectedProfile: $selectedProfile,
                                                  profiles: $viewModel.profileResults)

                Button {
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
                .opacity(viewModel.searchText.isEmpty ? 1.0 : 0.2)
                .frame(height: headerHeight)
            }
                   .contentShape(Rectangle())
                   .onTapGesture {
                       selectedProfile = nil
                   }
                   .padding(.horizontal, DesignConstants.Spacing.step4x)

            List {
                ForEach(viewModel.conversationResults, id: \.id) { conversation in
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ConversationAvatarView(conversation: conversation,
                                               size: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(conversation.topic)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)
                            switch conversation.kind {
                            case .dm:
                                Text(conversation.otherMember?.username ?? "")
                                    .font(.system(size: 14.0))
                                    .foregroundStyle(.colorTextSecondary)
                            case .group:
                                Text(conversation.memberNamesString)
                                    .font(.system(size: 14.0))
                                    .foregroundStyle(.colorTextSecondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.colorTextSecondary)
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(viewModel.profileResults, id: \.id) { profile in
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ProfileAvatarView(profile: profile, size: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(profile.name)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)
                            Text(profile.username)
                                .font(.system(size: 14.0))
                                .foregroundStyle(.colorTextSecondary)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .padding(0.0)
            .listStyle(.plain)

            Spacer()
        }
    }
}

#Preview {
    ConversationComposerView()
}
