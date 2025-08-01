import PhotosUI
import SwiftUI

// MARK: - Group Customization Sheet View Modifier

struct GroupCustomizationSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Bindable var editState: GroupEditState
    let onDismiss: () -> Void
    let draftTitle: String

    @FocusState private var isNameFocused: Bool

    func body(content: Content) -> some View {
        content
            .topDownSheet(
                isPresented: $isPresented,
                configuration: TopDownSheetConfiguration(
                    height: 100.0,
                    cornerRadius: 40.0,
                    horizontalPadding: DesignConstants.Spacing.step2x,
                    shadowRadius: 40.0,
                    dismissOnBackgroundTap: true,
                    dismissOnSwipeUp: false,
                    showDragIndicator: false
                )
            ) {
                GroupCustomizationContent(
                    editState: editState,
                    isNameFocused: _isNameFocused,
                    draftTitle: draftTitle,
                    onDismiss: {
                        isPresented = false
                    }
                )
            }
            .onChange(of: isPresented) { _, newValue in
                if !newValue {
                    onDismiss()
                }
            }
    }
}

// MARK: - Group Customization Content View

private struct GroupCustomizationContent: View {
    @Bindable var editState: GroupEditState
    @FocusState var isNameFocused: Bool
    let draftTitle: String
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            PhotosPicker(
                selection: $editState.imageSelection,
                matching: .images,
                photoLibrary: .shared()
            ) {
                GroupImageView(editState: editState)
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
                    .onSubmit {
                        onDismiss?()
                    }
            }

            ZStack {
                Circle()
                    .fill(.colorFillMinimal)

                Button {
                    withAnimation {
                        // Settings action - can be customized via a closure if needed
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
    }
}

// MARK: - Group Image View

private struct GroupImageView: View {
    let editState: GroupEditState

    var body: some View {
        if editState.imageState.isEmpty {
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
        } else {
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

// MARK: - View Extension

extension View {
    /// Presents a group customization sheet from the top of the screen
    /// - Parameters:
    ///   - isPresented: Binding to control sheet presentation
    ///   - editState: The group edit state to customize
    ///   - onDismiss: Closure called when sheet is dismissed with the updated edit state
    ///   - draftTitle: Default title to show when group name is empty
    func groupCustomizationSheet(
        isPresented: Binding<Bool>,
        editState: GroupEditState,
        onDismiss: @escaping () -> Void,
        draftTitle: String = "Untitled"
    ) -> some View {
        modifier(GroupCustomizationSheetModifier(
            isPresented: isPresented,
            editState: editState,
            onDismiss: onDismiss,
            draftTitle: draftTitle
        ))
    }
}
