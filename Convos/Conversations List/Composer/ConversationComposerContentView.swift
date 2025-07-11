import SwiftUI

struct ConversationComposerContentView: View {
    let composerState: ConversationComposerState
    @Binding var profileSearchText: String
    @Binding var selectedProfile: ProfileSearchResult?

    @FocusState private var isTextFieldFocused: Bool

    private let headerHeight: CGFloat = 72.0

    var resultsList: some View {
        List {
            ForEach(composerState.conversationResults, id: \.id) { conversation in
                FlashingListRowButton {
                } content: {
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ConversationAvatarView(conversation: conversation)
                            .frame(maxHeight: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(conversation.title)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)

                            switch conversation.kind {
                            case .dm:
                                Text(conversation.otherMember?.profile.username ?? "")
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
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSpacing(0.0)
            }

            ForEach(composerState.profileResults, id: \.id) { profileResult in
                let profile = profileResult.profile
                FlashingListRowButton {
                    composerState.add(profile: profileResult)
                } content: {
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ProfileAvatarView(profile: profile)
                            .frame(height: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(profile.name)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)
                            Text(profile.username)
                                .font(.system(size: 14.0))
                                .foregroundStyle(.colorTextSecondary)
                        }

                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSpacing(0.0)
            }
        }
        .background(.clear)
        .listStyle(.plain)
        .listRowSpacing(0.0)
        .opacity(
            (!composerState.profileResults.isEmpty ||
             !composerState.conversationResults.isEmpty ? 1.0 : 0.0))
        .padding(0)
    }

    var body: some View {
        VStack(spacing: 0.0) {
            if composerState.showProfileSearchHeader {
                // profile search header
                HStack(alignment: .top,
                       spacing: DesignConstants.Spacing.step2x) {
                    Text("To")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextSecondary)
                        .frame(height: headerHeight)

                    ConversationComposerProfilesField(
                        composerState: composerState,
                        searchText: $profileSearchText,
                        isTextFieldFocused: $isTextFieldFocused,
                        selectedProfile: $selectedProfile
                    )

                    Button {
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 24.0))
                            .foregroundStyle(.colorTextPrimary)
                            .padding(.horizontal, DesignConstants.Spacing.step2x)
                    }
                    .opacity(composerState.searchText.isEmpty ? 1.0 : 0.2)
                    .frame(height: headerHeight)
                }
                       .onTapGesture {
                           composerState.selectedProfile = nil
                           isTextFieldFocused = true
                       }
                       .padding(.horizontal, DesignConstants.Spacing.step4x)
                       .padding(.top, 4.0) // @jarodl temporary fix for iOS 26 toolbar issue
            }

            MessagesView(
                messagesRepository: composerState.messagesRepository
            )
            .overlay {
                if composerState.showResultsList {
                    resultsList
                }
            }

            Spacer().frame(height: 0.0)
        }
        .onAppear {
            isTextFieldFocused = true
        }
        .ignoresSafeArea()
    }
}

#Preview {
    @Previewable @State var composerState = ConversationComposerState(
        profileSearchRepository: MockProfileSearchRepository(),
        draftConversationRepo: MockDraftConversationRepository(),
        draftConversationWriter: MockDraftConversationWriter(),
        conversationConsentWriter: MockMessagingService(),
        conversationLocalStateWriter: MockConversationLocalStateWriter(),
        messagesRepository: MockMessagesRepository(conversation: .mock())
    )
    ConversationComposerContentView(
        composerState: composerState,
        profileSearchText: $composerState.searchText,
        selectedProfile: $composerState.selectedProfile,
    )
}
