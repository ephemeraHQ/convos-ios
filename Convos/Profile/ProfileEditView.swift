import PhotosUI
import SwiftUI

struct ProfileView: View {
    @State var displayName: String = ""
    @State var useForNewConvos: Bool = false
    @State private var imageSelection: PhotosPickerItem?

    var backgroundColor: Color {
        Color(UIColor.systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileAvatarView(profile: .mock())
                        .frame(maxWidth: .infinity, maxHeight: 175.0)

                    PhotosPicker(selection: $imageSelection,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("Photo Picker", systemImage: "photo.on.rectangle.angled")
                            .tint(.white)
                            .labelStyle(.iconOnly)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(.gray))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowSpacing(0.0)
                .listRowInsets(.all, DesignConstants.Spacing.step2x)

                Section {
                    HStack {
                        TextField("Somebody", text: $displayName)

                        Button {
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Toggle("Use for new convos", isOn: $useForNewConvos)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Randomizer")
                            Text("american • gender neutral")
                        }
                        Spacer()
                        VStack {
                            Spacer()
                            Image(systemName: "chevron.right")
                            Spacer()
                        }
                    }
                }
            }
            .contentMargins(.top, 0.0)
            .listSectionMargins(.all, 0.0)
            .listRowInsets(.all, 0.0)
            .listSectionSpacing(DesignConstants.Spacing.step6x)
            .background(backgroundColor)
            .scrollContentBackground(.hidden)
            .scrollClipDisabled()
            .background(backgroundColor)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
}
