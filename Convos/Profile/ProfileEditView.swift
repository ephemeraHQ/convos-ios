import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ConversationViewModel

    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: DesignConstants.Spacing.step6x) {
                            ProfileAvatarView(
                                profile: viewModel.profile,
                                profileImage: viewModel.profileImage
                            )
                            .frame(width: 160.0, height: 160.0)

                            ImagePickerButton(
                                currentImage: $viewModel.profileImage,
                                showsCurrentImage: false,
                                symbolSize: 20.0
                            )
                            .frame(width: 44.0, height: 44.0)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                .listRowSeparator(.hidden)
                .listRowSpacing(0.0)
                .listRowInsets(.all, DesignConstants.Spacing.step2x)
                .listSectionMargins(.top, 0.0)
                .listSectionSeparator(.hidden)

                Section {
                    HStack {
                        TextField("Somebody", text: $viewModel.editingDisplayName)

//                        Button {
//                        } label: {
//                            Image(systemName: "shuffle")
//                        }
//                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Toggle(isOn: $viewModel.useDisplayNameForNewConvos) {
                        Text("Quickname")
                            .foregroundStyle(.colorTextPrimary)
                    }
                } footer: {
                    Text("Use this name quickly in new convos")
                        .foregroundStyle(.colorTextSecondary)
                }

//                Section {
//                    Toggle("Use for new convos", isOn: $useForNewConvos)
//                }
//
//                Section {
//                    HStack {
//                        VStack(alignment: .leading) {
//                            Text("Randomizer")
//                            Text("american • gender neutral")
//                        }
//                        Spacer()
//                        VStack {
//                            Spacer()
//                            Image(systemName: "chevron.right")
//                            Spacer()
//                        }
//                    }
//                }
            }
            .contentMargins(.top, 0.0)
            .listSectionMargins(.all, 0.0)
            .listRowInsets(.all, 0.0)
            .listSectionSpacing(DesignConstants.Spacing.step6x)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        viewModel.onProfileSettingsDismissed()
                    }
                    .tint(.colorBackgroundInverted)
                }
            }
        }
    }
}

#Preview {
    ProfileView(viewModel: .mock)
}
