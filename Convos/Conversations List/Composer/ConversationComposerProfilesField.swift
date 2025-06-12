import OrderedCollections
import SwiftUI

// This exists to get around the selected state for Profile "chips"
// needing to go outside the scroll view clipping area
struct VerticalEdgeClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.minX - (rect.width / 2.0),
                            y: rect.minY,
                            width: rect.width * 2.0,
                            height: rect.height))
        return path
    }
}

struct ConversationComposerProfilesField: View {
    let composerState: ConversationComposerState
    @State private var profileChipsHeight: CGFloat = 0.0
    @Binding var searchText: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    @Binding var selectedProfile: ProfileSearchResult?
    @State var searchTextEditingEnabled: Bool = true

    private let profileChipsMaxHeight: CGFloat = 150.0

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: DesignConstants.Spacing.step2x) {
                        ForEach(composerState.profilesAdded, id: \.id) { profileResult in
                            let profile = profileResult.profile
                            ComposerProfileChipView(profile: profile,
                                                    isSelected: selectedProfile == profileResult)
                            .tag(profile)
                            .onTapGesture {
                                selected(profile: profileResult)
                            }
                            .offset(y: -1.75)
                        }

                        FlowLayoutTextEditor(
                            text: $searchText,
                            editingEnabled: $searchTextEditingEnabled,
                            isFocused: isTextFieldFocused,
                            maxTextFieldWidth: reader.size.width,
                            onBackspaceWhenEmpty: {
                                backspaceOnEmpty()
                            }, onEndedEditing: {
                                selectedProfile = nil
                            }
                        )
                        .id("textField")
                        .padding(.bottom, 4.0)
                        .opacity(selectedProfile != nil ? 0.0 : 1.0)
                    }
                    .padding(.vertical, DesignConstants.Spacing.step4x)
                    .background(HeightReader())
                    .onPreferenceChange(HeightPreferenceKey.self) { height in
                        profileChipsHeight = min(height, profileChipsMaxHeight)
                    }
                    .padding(.top, 4.0)
                    .onChange(of: selectedProfile) {
                        searchTextEditingEnabled = selectedProfile == nil
                        guard selectedProfile != nil else { return }
                        isTextFieldFocused.wrappedValue = true
                        withAnimation {
                            proxy.scrollTo(selectedProfile,
                                           anchor: .center)
                        }
                    }
                    .onChange(of: searchText) {
                        textChanged(searchText)
                        if profileChipsHeight >= profileChipsMaxHeight {
                            withAnimation {
                                proxy.scrollTo("textField", anchor: .center)
                            }
                        }
                    }
                    .scrollBounceBehavior(.always)
                }
                .scrollClipDisabled()
                .clipShape(VerticalEdgeClipShape())
            }
        }
        .frame(height: profileChipsHeight)
    }

    func selected(profile: ProfileSearchResult) {
        selectedProfile = selectedProfile == profile ? nil : profile
    }

    func backspaceOnEmpty() {
        if let selectedProfile {
            composerState.remove(profile: selectedProfile)
            self.selectedProfile = nil
        } else {
            selectedProfile = composerState.profilesAdded.last
        }
    }

    func textChanged(_ text: String) {
    }
}

#Preview {
    @Previewable @State var composerState: ConversationComposerState = .init(
        profileSearchRepository: MockProfileSearchRepository(),
        draftConversationRepo: MockDraftConversationRepository(),
        draftConversationWriter: MockDraftConversationWriter(),
        conversationConsentWriter: MockMessagingService(),
        conversationLocalStateWriter: MockConversationLocalStateWriter(),
        messagesRepository: MockMessagesRepository(conversation: .mock())
    )
    @Previewable @FocusState var textFieldFocusState: Bool

    VStack {
        HStack {
            Spacer().frame(width: 40)
            ConversationComposerProfilesField(
                composerState: composerState,
                searchText: $composerState.searchText,
                isTextFieldFocused: $textFieldFocusState,
                selectedProfile: $composerState.selectedProfile
            )
            Spacer().frame(width: 40)
        }
        Text("Content Below")

        Spacer()
    }
}
