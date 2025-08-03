import PhotosUI
import SwiftUI

private struct ConversationEditImageView: View {
    @State var imageState: PhotosPickerImage.State = .empty
    @State var currentConversationImage: UIImage?

    var body: some View {
        if imageState.isEmpty {
            if let currentConversationImage = currentConversationImage {
                Image(uiImage: currentConversationImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(.black)
                    Image(systemName: "photo.on.rectangle.fill")
                        .font(.system(size: 24.0))
                        .foregroundColor(.white)
                }
            }
        } else {
            switch imageState {
            case .loading:
                ProgressView()
            case .failure:
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Error loading image")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            case .empty:
                EmptyView()
            }
        }
    }
}

struct ConversationQuickEditView: View {
    let draftTitle: String
    @State var conversationName: String = ""
    @State var imageSelection: PhotosPickerItem? {
        didSet {
            if let imageSelection {
//                imageLoadingTask?.cancel()
//                imageLoadingTask = Task {
//                    await loadSelectedImage(imageSelection)
//                }
            }
        }
    }
    @State var imageState: PhotosPickerImage.State = .empty

    @FocusState var isNameFocused: Bool

    var body: some View {
        HStack {
            PhotosPicker(
                selection: $imageSelection,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ConversationEditImageView(currentConversationImage: nil)
                    .frame(width: 52.0, height: 52.0)
            }

            Group {
                TextField(draftTitle, text: $conversationName)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16.0)
                    .font(.system(size: 17.0))
                    .foregroundStyle(.colorTextPrimary)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        //                        onDismiss?()
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52.0)
            .background(
                Capsule()
                    .stroke(.gray.opacity(0.2), lineWidth: 1.0)
            )

            Button {
            } label: {
                Image(systemName: "gear")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.3))
                    .padding(.horizontal, 12.0)
            }
            .frame(width: 52.0, height: 52.0)
            .background(Circle().fill(.gray.opacity(0.2)))
        }
        .frame(maxWidth: .infinity)
//        .padding(DesignConstants.Spacing.step6x)
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                isNameFocused = true
//            }
//        }
    }
}

#Preview {
    ConversationQuickEditView(draftTitle: "New convo")
}
