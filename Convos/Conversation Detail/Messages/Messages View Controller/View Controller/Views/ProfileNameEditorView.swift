import PhotosUI
import SwiftUI

struct ProfileNameEditorView: View {
    @Binding var profile: Profile
    @Binding var profileName: String
    @Binding var showingProfileNameEditor: Bool
    let profileEditorAnimationNamespace: Namespace.ID
    @State private var imageSelection: PhotosPickerItem?
    @FocusState private var profileNameFieldFocused: Bool

    var body: some View {
        Group {
            HStack {
                PhotosPicker(
                    selection: $imageSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Photo Picker", systemImage: "photo.on.rectangle.angled")
                        .tint(.white)
                        .labelStyle(.iconOnly)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(.gray))
                        .foregroundColor(.white)
                }
                .matchedGeometryEffect(
                    id: "button",
                    in: profileEditorAnimationNamespace
                )

                TextField(profile.displayName, text: $profileName)
                    .focused($profileNameFieldFocused)
                    .onAppear {
                        profileNameFieldFocused = true
                    }

                Button {
                    showingProfileNameEditor = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 20.0))
            .padding(DesignConstants.Spacing.stepX)
            .matchedGeometryEffect(
                id: "container",
                in: profileEditorAnimationNamespace
            )
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var profileName: String = ""
    @Previewable @State var showingProfileNameEditor: Bool = true
    @Previewable @Namespace var profileEditorAnimationNamespace: Namespace.ID
    ProfileNameEditorView(
        profile: $profile,
        profileName: $profileName,
        showingProfileNameEditor: $showingProfileNameEditor,
        profileEditorAnimationNamespace: profileEditorAnimationNamespace
    )
}
