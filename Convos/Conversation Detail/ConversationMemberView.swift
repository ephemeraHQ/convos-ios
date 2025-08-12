import SwiftUI

struct ConversationMemberView: View {
    @Bindable var viewModel: ConversationViewModel
    let member: ConversationMember

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack {
                        ProfileAvatarView(profile: member.profile)
                            .frame(width: 160.0, height: 160.0)

                        Text(member.profile.displayName.capitalized)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(.colorTextPrimary)

                        if member.isCurrentUser {
                            Text("You")
                                .font(.headline)
                                .foregroundStyle(.colorTextSecondary)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            .listSectionMargins(.top, 0.0)
            .listSectionSeparator(.hidden)

            if !member.isCurrentUser {
                Section {
                    Button {
                    } label: {
                        Text("Block")
                            .foregroundStyle(.colorCaution)
                    }
                } footer: {
                    Text("Block \(member.profile.displayName.capitalized) and leave the convo")
                        .foregroundStyle(.colorTextSecondary)
                }

                Section {
                    Button {
                    } label: {
                        Text("Remove")
                            .foregroundStyle(.colorTextSecondary)
                    }
                } footer: {
                    Text("Remove \(member.profile.displayName.capitalized) from the convo")
                }
            }
        }
    }
}

#Preview {
    ConversationMemberView(viewModel: .mock, member: .mock())
}
