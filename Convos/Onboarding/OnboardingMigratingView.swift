import SwiftUI

@Observable
class OnboardingMigratingViewModel {
    let convos: ConvosClient
    var authenticationError: String?

    init(convos: ConvosClient) {
        self.convos = convos
    }

    func signIn() {
        Task {
            do {
                try await convos.signIn()
            } catch {
                Logger.error("Error signing in: \(error)")
                authenticationError = error.localizedDescription
            }
        }
    }
}

struct OnboardingMigratingView: View {
    @State private var viewModel: OnboardingMigratingViewModel
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
            }
            .padding(.leading, DesignConstants.Spacing.step3x)
            .padding(.top, 10.0)

            Spacer()

            VStack(spacing: DesignConstants.Spacing.step4x) {
                Text("Welcome to the new Convos")
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
                Button("Sign back in") {
                    viewModel.signIn()
                }
                .convosButtonStyle(.rounded(fullWidth: true))
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.top, DesignConstants.Spacing.step2x)
            .padding(.bottom, DesignConstants.Spacing.step6x)
        }
        .padding(.horizontal, DesignConstants.Spacing.step3x)
    }
}
