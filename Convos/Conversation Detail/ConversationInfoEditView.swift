import ConvosCore
import PhotosUI
import SwiftUI
import SwiftUIIntrospect

struct ConversationInfoEditView: View {
    @Bindable var viewModel: ConversationViewModel

    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: DesignConstants.Spacing.step6x) {
                            ConversationAvatarView(
                                conversation: viewModel.conversation,
                                conversationImage: viewModel.conversationImage
                            )
                            .frame(width: 160.0, height: 160.0)

                            ImagePickerButton(
                                currentImage: $viewModel.conversationImage,
                                showsCurrentImage: false,
                                symbolSize: 20.0
                            )
                            .frame(width: 44.0, height: 44.0)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                .listSectionMargins(.top, 0.0)
                .listSectionSeparator(.hidden)

                Section {
                    TextField(viewModel.conversationNamePlaceholder, text: $viewModel.conversationName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 166.0)
                        .introspect(.textField, on: .iOS(.v26)) { textField in
                            textField.convos_setMaxLength(NameLimits.maxConversationNameLength)
                        }
                    TextField(
                        viewModel.conversationDescriptionPlaceholder,
                        text: $viewModel.conversationDescription
                    )
                    .lineLimit(5)
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        viewModel.onConversationSettingsDismissed()
                    }
                    .tint(.colorBackgroundInverted)
                }
            }
        }
    }
}

#Preview {
    ConversationInfoEditView(viewModel: .mock)
}
