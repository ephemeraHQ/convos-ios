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
    @State private var profileChipsHeight: CGFloat = 0.0
    @Binding var searchText: String
    @Binding var selectedProfile: Profile? {
        didSet {
            searchTextEditingEnabled = selectedProfile == nil
        }
    }
    @State var searchTextEditingEnabled: Bool = true
    @Binding var profiles: OrderedSet<Profile>

    private let profileChipsMaxHeight: CGFloat = 150.0

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: DesignConstants.Spacing.step2x) {
                        ForEach(profiles, id: \.id) { profile in
                            ComposerProfileChipView(profile: profile,
                                                    isSelected: selectedProfile == profile)
                            .tag(profile)
                            .onTapGesture {
                                selected(profile: profile)
                            }
                            .offset(y: -1.75)
                        }

                        FlowLayoutTextEditor(text: $searchText,
                                             editingEnabled: $searchTextEditingEnabled,
                                             maxTextFieldWidth: reader.size.width) {
                            backspaceOnEmpty()
                        }
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

    func selected(profile: Profile) {
        selectedProfile = selectedProfile == profile ? nil : profile
    }

    func backspaceOnEmpty() {
        if let selectedProfile {
            profiles.remove(selectedProfile)
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
    @Previewable @State var selectedProfile: Profile?
    @Previewable @State var profileResults: OrderedSet<Profile> = [
        .mock(), .mock(), .mock(), .mock(), .mock(),
        .mock(), .mock(), .mock(), .mock(), .mock(),
        .mock(), .mock(), .mock(), .mock(), .mock()
    ]

    VStack {
        HStack {
            Spacer().frame(width: 40)
            ConversationComposerProfilesField(searchText: $searchText,
                                              selectedProfile: $selectedProfile,
                                              profiles: $profileResults)
            Spacer().frame(width: 40)
        }
        Text("Content Below")

        Spacer()
    }
}
