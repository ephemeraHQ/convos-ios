import SwiftUI

struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel
    @State var presentingCreateContactCard: Bool = false
    @State var presentingImportContactCard: Bool = false

    init(convos: ConvosClient) {
        _viewModel = State(initialValue: .init(convos: convos))
    }

    var body: some View {
        VStack(spacing: DesignConstants.Spacing.step4x) {
            HStack(spacing: DesignConstants.Spacing.step2x) {
                Circle()
                    .foregroundStyle(.colorOrange)
                    .frame(width: DesignConstants.ImageSizes.smallAvatar,
                           height: DesignConstants.ImageSizes.smallAvatar)
                Text("Convos")
                    .font(.subheadline)
                    .foregroundStyle(.colorTextPrimary)

                Spacer()

                if viewModel.authAllowsSignIn {
                    Button("Sign in") {
                        viewModel.signIn()
                    }
                    .convosButtonStyle(.text)
                }
            }
            .padding(.leading, DesignConstants.Spacing.step3x)
            .padding(.top, 10.0)

            Spacer()

            VStack(spacing: DesignConstants.Spacing.step4x) {
                Text("Not another chat app")
                    .font(.system(size: 56.0, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Super secure · Decentralized · Universal")
                    .font(.subheadline)
                    .foregroundStyle(.colorTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignConstants.Spacing.stepX)

            Spacer()

            VStack(spacing: DesignConstants.Spacing.step4x) {
                Button("Create your Contact Card") {
                    presentingCreateContactCard = true
                }
                .convosButtonStyle(.rounded(fullWidth: true))

                LegalView()
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.top, DesignConstants.Spacing.step2x)
            .padding(.bottom, DesignConstants.Spacing.step6x)
        }
        .padding(.horizontal, DesignConstants.Spacing.step3x)
        .fullScreenCover(isPresented: $presentingCreateContactCard) {
            ContactCardCreateView(name: $viewModel.name,
                                  imageState: $viewModel.imageState,
                                  nameIsValid: $viewModel.nameIsValid,
                                  nameError: $viewModel.nameError,
                                  isEditing: $viewModel.isEditingContactCard,
                                  importCardAction: {
                                      presentingImportContactCard = true
                                  }, submitAction: viewModel.createContactCard)
        }
    }
}

private struct LegalView: View {
    var body: some View {
        Group {
            Text("When you create a contact card, you agree to the Convos ")
                + Text("[Terms](https://xmtp.org/terms)")
                .underline()
                + Text(" and ")
                + Text("[Privacy Policy](https://xmtp.org/privacy)")
                .underline()
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .tint(.secondary)
        .foregroundColor(.secondary)
    }
}

#Preview {
    OnboardingView(
        convos: .mock()
    )
}
