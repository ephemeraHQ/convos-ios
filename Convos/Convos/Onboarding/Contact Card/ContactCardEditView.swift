//
//  ContactCardEditView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/15/25.
//

import SwiftUI
import PhotosUI

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

struct ContactCardAvatarView: View {
    
    @State private var cameraButtonSize: ContactCardCameraButton.Size = .regular
    @Binding var imageState: ContactCardImage.State {
        didSet {
            withAnimation {
                self.cameraButtonSize = imageState.isEmpty ? .regular : .compact
            }
        }
    }
    @State private var imageSelection: PhotosPickerItem? = nil
    
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
                    case .failure(let error):
                        Text("Error: \(error.localizedDescription)")
                    case .empty:
                        EmptyView()
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    }
                    
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

struct ContactCardEditView: View {
    @Binding var name: String
    @Binding var imageState: ContactCardImage.State
    @Binding var nameIsValid: Bool
    @Binding var nameError: String?
    @FocusState.Binding var isNameFocused: Bool
    let importAction: () -> Void
    
    var body: some View {
        VStack(spacing: 10.0) {
            HStack(alignment: .top) {
                ContactCardAvatarView(imageState: $imageState)
                
                Spacer()
                
                Button {
                    importAction()
                } label: {
                    Text("Import")
                        .font(DesignConstants.Fonts.buttonText)
                        .foregroundStyle(Color.colorFillSecondary)
                        .padding(.horizontal, DesignConstants.Spacing.step3x)
                        .padding(.vertical, DesignConstants.Spacing.step2x)
                }
            }
            
            LabeledTextField(label: "Name",
                             prompt: "Nice to meet you",
                             textFieldBorderColor: (nameError == nil ? .colorBorderSubtle : .colorCaution),
                             text: $name,
                             isFocused: $isNameFocused)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .environment(\.colorScheme, .dark)
        }
        .padding(DesignConstants.Spacing.medium)
        .background(.backgroundSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.regular))
        .shadow(color: .colorDarkAlpha15, radius: 8, x: 0, y: 4)
    }
}

#Preview {
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var name: String = ""
    @Previewable @State var nameIsValid: Bool = true
    @Previewable @State var nameError: String? = nil
    @Previewable @FocusState var isNameFocused: Bool
    
    ContactCardEditView(name: $name, imageState: $imageState, nameIsValid: $nameIsValid, nameError: $nameError, isNameFocused: $isNameFocused, importAction: { })
}
