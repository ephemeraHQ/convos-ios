import PhotosUI
import SwiftUI

extension PhotosPickerItem {
    @MainActor
    func loadContactCardImage() async -> ContactCardImage.State {
        do {
            if let contactCardImage = try await loadTransferable(type: ContactCardImage.self) {
                return .success(contactCardImage.image)
            } else {
                return .empty
            }
        } catch {
            return .failure(error)
        }
    }
}

struct ContactCardImage: Transferable {
    enum State {
        case loading, empty, success(Image), failure(Error)
        var isEmpty: Bool {
            if case .empty = self {
                return true
            }
            return false
        }
    }

    enum ContactCardImageError: Error {
        case importFailed
    }

    let image: Image

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            #if canImport(AppKit)
                guard let nsImage = NSImage(data: data) else {
                    throw ContactCardImageError.importFailed
                }
                let image = Image(nsImage: nsImage)
                return ContactCardImage(image: image)
            #elseif canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw ContactCardImageError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return ContactCardImage(image: image)
            #else
                throw ContactCardImageError.importFailed
            #endif
        }
    }
}

struct ContactCardCameraButton: View {
    enum Size {
        case compact, regular

        var font: Font {
            switch self {
            case .regular:
                return DesignConstants.Fonts.standard
            case .compact:
                return DesignConstants.Fonts.medium
            }
        }

        var spacerOffset: CGFloat {
            switch self {
            case .regular:
                return 0.0
            case .compact:
                return 56.0
            }
        }
    }

    @Binding var size: Size

    var body: some View {
        GeometryReader { reader in
            ZStack {
                Image(systemName: "camera.fill")
                    .font(size.font)
                    .foregroundStyle(DesignConstants.Colors.light)
            }
            .frame(width: reader.size.width, height: reader.size.height)
            .background(.colorFillMinimal)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .inset(by: 0.5)
                    .stroke(.colorBorderSubtle, lineWidth: 1.0)
            )
        }
    }
}

struct ContactCardAvatarView<Content: View & Sendable>: View {
    @Binding var isEditing: Bool
    @Binding var imageState: ContactCardImage.State {
        didSet {
            withAnimation {
                self.cameraButtonSize = imageState.isEmpty ? .regular : .compact
            }
        }
    }

    let emptyView: () -> Content

    @State private var cameraButtonSize: ContactCardCameraButton.Size = .regular
    @State private var imageSelection: PhotosPickerItem?

    let defaultSize: CGFloat = 96.0

    var body: some View {
        GeometryReader { reader in
            let size: CGFloat = min(reader.size.width, reader.size.height)
            PhotosPicker(selection: $imageSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                ZStack {
                    switch self.imageState {
                    case .loading:
                        ProgressView()
                            .frame(width: size, height: size)
                    case let .failure(error):
                        Text("Error: \(error.localizedDescription)")
                    case .empty:
                        emptyView()
                            .overlay(
                                Circle()
                                    .inset(by: 0.5)
                                    .stroke(.colorBorderSubtle, lineWidth: 1.0)
                            )
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    }

                    if isEditing {
                        VStack(spacing: 0.0) {
                            Spacer()
                                .frame(height: cameraButtonSize.spacerOffset)

                            HStack(spacing: 0.0) {
                                ContactCardCameraButton(size: $cameraButtonSize)

                                Spacer()
                                    .frame(width: cameraButtonSize.spacerOffset)
                            }
                        }
                        .frame(width: size, height: size)
                    }
                }
            }
            .disabled(!isEditing)
            .onChange(of: imageSelection) {
                if let imageSelection {
                    self.imageState = .loading
                    Task {
                        let imageState = await imageSelection.loadContactCardImage()
                        withAnimation {
                            self.imageState = imageState
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .frame(width: defaultSize, height: defaultSize)
    }
}

#Preview {
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var name = "Robert Adams"
    @Previewable @State var isEditing = true

    VStack {
        ContactCardAvatarView(isEditing: $isEditing, imageState: $imageState) {
            MonogramView(name: name)
        }

        Button(isEditing ? "Done" : "Edit") {
            isEditing.toggle()
        }
        .padding()
    }
}
