import SwiftUI

struct ConversationComposerContentView: View {
    @State private var composerState: ConversationComposerState
    @FocusState private var isTextFieldFocused: Bool

    init(composerState: ConversationComposerState) {
        self.composerState = composerState
    }

    init(composer: any DraftConversationComposerProtocol) {
        _composerState = State(
            initialValue: .init(
                profileSearchRepository: composer.profileSearchRepository,
                draftConversationRepo: composer.draftConversationRepository,
                draftConversationWriter: composer.draftConversationWriter,
                messagesRepository: composer.draftConversationRepository.messagesRepository
            )
        )
    }

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
                .listRowBackground(Color.colorBackgroundPrimary)
                .listRowInsets(EdgeInsets())
                .listRowSpacing(0.0)
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0.0)
        .opacity(
            (!composerState.profileResults.isEmpty ||
             !composerState.conversationResults.isEmpty ? 1.0 : 0.0))
        .padding(0)
    }

    var body: some View {
        VStack(spacing: 0.0) {
            if !composerState.hasSentMessage {
                // profile search header
                HStack(alignment: .top,
                       spacing: DesignConstants.Spacing.step2x) {
                    Text("To")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextSecondary)
                        .frame(height: headerHeight)

                    ConversationComposerProfilesField(
                        composerState: composerState,
                        searchText: $composerState.searchText,
                        isTextFieldFocused: $isTextFieldFocused,
                        selectedProfile: $composerState.selectedProfile
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
                       .contentShape(Rectangle())
                       .onTapGesture {
                           composerState.selectedProfile = nil
                           isTextFieldFocused = true
                       }
                       .padding(.horizontal, DesignConstants.Spacing.step4x)
                       .background(.colorBackgroundPrimary)
            }

            MessagesView(messagesRepository: composerState.messagesRepository)
                .ignoresSafeArea()
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
        messagesRepository: MockMessagesRepository(conversation: .mock())
    )
    ConversationComposerContentView(
        composerState: composerState
    )
}
