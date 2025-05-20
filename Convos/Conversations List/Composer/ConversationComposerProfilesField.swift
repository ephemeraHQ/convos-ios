import SwiftUI

struct VerticalEdgeClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.minX-(rect.width / 2.0),
                            y: rect.minY,
                            width: rect.width * 2.0,
                            height: rect.height))
        return path
    }
}

struct ConversationComposerProfilesField: View {
    @State private var profileTagsHeight: CGFloat = 0.0
    @Binding var searchText: String
    @Binding var selectedProfile: Profile? {
        didSet {
            searchTextEditingEnabled = selectedProfile == nil
        }
    }
    @State var searchTextEditingEnabled: Bool = true
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
                                             editingEnabled: $searchTextEditingEnabled,
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
            .scrollClipDisabled()
            .clipShape(VerticalEdgeClipShape())
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
    @Previewable @State var selectedProfile: Profile? = nil
    @Previewable @State var profileResults: [Profile] = [
        .mock(), .mock(), .mock(), .mock()
    ]

    VStack {
        HStack {
            Spacer().frame(width: 40)
            ConversationComposerProfilesField(searchText: $searchText,
                                              selectedProfile: $selectedProfile,
                                              profiles: $profileResults)
            Spacer().frame(width: 40)
        }

        Spacer()
    }
}
