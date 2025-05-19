import SwiftUI

struct ConversationComposerProfilesField: View {
    @State private var profileTagsHeight: CGFloat = 0.0
    @Binding var searchText: String

    @State private var selectedProfile: Profile?
    @Binding var profiles: [Profile]

    private let profileTagsMaxHeight: CGFloat = 150.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GeometryReader { reader in
                    FlowLayout(spacing: DesignConstants.Spacing.step2x) {
                        ForEach(profiles, id: \.id) { profile in
                            ComposerProfileTagView(profile: profile,
                                                   isSelected: selectedProfile == profile)
                            .tag(profile)
                            .onTapGesture {
                                selected(profile: profile)
                            }
                        }

                        FlowLayoutTextEditor(text: $searchText,
                                             maxTextFieldWidth: reader.size.width) {
                            backspaceOnEmpty()
                        }
                                             .padding(.bottom, 4.0)
                                             .opacity(selectedProfile != nil ? 0.0 : 1.0)
                    }
                    .padding(.vertical, DesignConstants.Spacing.step4x)
                    .background(HeightReader())
                    .onPreferenceChange(HeightPreferenceKey.self) { height in
                        profileTagsHeight = min(height, profileTagsMaxHeight)
                    }
                }
                .padding(.top, 4.0)
                .frame(height: profileTagsHeight)
                .onChange(of: selectedProfile) {
                    withAnimation {
                        proxy.scrollTo(selectedProfile,
                                       anchor: .center)
                    }
                }
                .onChange(of: searchText) {
                    textChanged(searchText)
                    withAnimation {
                        proxy.scrollTo("textField", anchor: .leading)
                    }
                }
                .scrollBounceBehavior(.always)
            }
        }
        .frame(height: profileTagsHeight)
    }

    func selected(profile: Profile) {
        selectedProfile = selectedProfile == profile ? nil : profile
    }

    func backspaceOnEmpty() {
        if let selectedProfile {
            profiles.removeAll { $0.id == selectedProfile.id }
            self.selectedProfile = nil
        } else {
            selectedProfile = profiles.last
        }
    }

    func textChanged(_ text: String) {
    }
}

#Preview {
    @Previewable @State var searchText: String = ""
    @Previewable @State var profileResults: [Profile] = [
        .mock(), .mock(), .mock(), .mock()
    ]

    VStack {
        HStack {
            Spacer().frame(width: 40)
            ConversationComposerProfilesField(searchText: $searchText,
                                              profiles: $profileResults)
            Spacer().frame(width: 40)
        }

        Text("test")

        Spacer()
    }
}
