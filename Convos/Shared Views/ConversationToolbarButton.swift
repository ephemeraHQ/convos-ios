import PhotosUI
import SwiftUI

enum PhotosPickerImageError: Error {
    case importFailed
}

struct PhotosPickerImage: Transferable {
    enum State {
        case loading, empty, success(UIImage), failure(Error)
        var isEmpty: Bool {
            if case .empty = self {
                true
            } else {
                false
            }
        }
    }

    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let uiImage = UIImage(data: data) else {
                throw PhotosPickerImageError.importFailed
            }
            return PhotosPickerImage(image: uiImage)
        }
    }
}

extension PhotosPickerItem {
    @MainActor
    func loadImage() async -> PhotosPickerImage.State {
        do {
            if let photosPickerImage = try await loadTransferable(type: PhotosPickerImage.self) {
                return .success(photosPickerImage.image)
            } else {
                return .empty
            }
        } catch {
            return .failure(error)
        }
    }
}

struct ConversationToolbarButton: View {
    let conversation: Conversation
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction

    let draftTitle: String
    let subtitle: String
    @State private var editState: GroupEditState
    @State private var presentingCustomizeSheet: Bool = false
    @FocusState private var isNameFocused: Bool

    init(
        conversation: Conversation,
        groupMetadataWriter: any GroupMetadataWriterProtocol,
        draftTitle: String = "New convo",
        subtitle: String = "Customize",
    ) {
        self.conversation = conversation
        self.draftTitle = draftTitle
        self.subtitle = subtitle
        self.groupMetadataWriter = groupMetadataWriter
        self._editState = State(initialValue: GroupEditState(
            conversation: conversation,
            groupMetadataWriter: groupMetadataWriter
        ))
    }

    var body: some View {
        Button {
            presentingCustomizeSheet = true
        } label: {
            HStack(spacing: 0.0) {
                ConversationAvatarView(conversation: conversation)
                    .frame(width: 36.0, height: 36.0)

                VStack(alignment: .leading, spacing: 0.0) {
                    if !conversation.isDraft, let name = conversation.name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 16.0, weight: .medium))
                            .foregroundStyle(.colorTextPrimary)
                    } else {
                        Text(draftTitle)
                            .font(.system(size: 16.0, weight: .medium))
                    }
                    Text(subtitle)
                        .font(.system(size: 12.0, weight: .regular))
                        .foregroundStyle(.colorTextSecondary)
                }
                .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
        }
        .padding(DesignConstants.Spacing.step2x)
        .glassEffect()
        .padding(.top, DesignConstants.Spacing.stepX) // @jarodl avoids dynamic island
        .onAppear {
            editState.onAppear()
        }
        .onDisappear {
            editState.onDisappear()
        }
        .cachedImage(for: conversation) { _ in
            editState.onImageCacheUpdate()
        }
        .topDownSheet(
            isPresented: $presentingCustomizeSheet,
            configuration: TopDownSheetConfiguration(
                height: 100.0,
                cornerRadius: 40.0,
                horizontalPadding: DesignConstants.Spacing.step2x,
                shadowRadius: 40.0,
                dismissOnBackgroundTap: true,
                dismissOnSwipeUp: false,
                showDragIndicator: false
            ),
            content: {
                HStack {
                    PhotosPicker(selection: $editState.imageSelection,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        switch editState.imageState {
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
                        case .empty:
                            if let currentConversationImage = editState.currentConversationImage {
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
                        case let .success(image):
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(Circle())
                        }
                    }

                    ZStack {
                        Capsule()
                            .stroke(.colorFillMinimal, lineWidth: 1.0)

                        TextField(draftTitle, text: $editState.groupName)
                            .font(.system(size: 17.0))
                            .foregroundStyle(.colorTextPrimary)
                            .multilineTextAlignment(.center)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    }

                    ZStack {
                        Circle()
                            .fill(.colorFillMinimal)

                        Button {
                            withAnimation {
                            }
                        } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.colorTextSecondary)
                                .font(.system(size: 24.0))
                        }
                    }
                }
                .padding(DesignConstants.Spacing.step6x)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isNameFocused = true
                    }
                }
            })
    }
}

#Preview {
    @Previewable @State var conversation: Conversation = .mock()

    VStack {
        ConversationToolbarButton(conversation: conversation, groupMetadataWriter: MockGroupMetadataWriter())
    }
}
