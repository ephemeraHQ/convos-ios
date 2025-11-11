import ConvosCore
import SwiftUI

/// A view that displays the appropriate onboarding content based on the coordinator's state
struct ConversationOnboardingView: View {
    @Bindable var coordinator: ConversationOnboardingCoordinator
    let onTapSetupQuickname: () -> Void
    let onUseQuickname: (Profile, UIImage?) -> Void
    let onSaveAsQuickname: (Profile) -> Void

    private var permissionState: NotificationPermissionState? {
        switch coordinator.state {
        case .requestNotifications:
                .request
        case .notificationsDenied:
                .denied
        case .notificationsEnabled:
                .enabled
        default:
            nil
        }
    }

    var body: some View {
        if coordinator.inProgress || coordinator.isWaitingForInviteAcceptance {
            VStack(spacing: DesignConstants.Spacing.step3x) {
                // Show "Invite accepted" message if waiting for invite
                if coordinator.isWaitingForInviteAcceptance {
                    InviteAcceptedView()
                }

                // Show the current onboarding state
                switch coordinator.state {
                case .idle:
                    EmptyView()
                case .setupQuickname(let autoDismiss):
                    SetupQuicknameView(
                        autoDismiss: autoDismiss,
                        onAddName: {
                            coordinator.didTapSetupQuickname()
                            onTapSetupQuickname()
                        },
                        onDismiss: {
                            Task {
                                await coordinator.setupQuicknameDidAutoDismiss()
                            }
                        }
                    )

                case .saveAsQuickname(let profile):
                    UseAsQuicknameView(
                        profile: .constant(profile),
                        onUseAsQuickname: {
                            onSaveAsQuickname(profile)
                        },
                        onDismiss: {
                            Task {
                                await coordinator.saveAsQuicknameDidAutodismiss()
                            }
                        }
                    )

                case let .addQuickname(settings, profileImage):
                    AddQuicknameView(
                        profile: .constant(settings.profile),
                        profileImage: .constant(profileImage),
                        onUseProfile: { profile, image in
                            onUseQuickname(profile, image)
                            Task {
                                await coordinator.didSelectQuickname()
                            }
                        }, onDismiss: {
                            Task {
                                await coordinator.addQuicknameDidAutoDismiss()
                            }
                        }
                    )

                case .requestNotifications,
                        .notificationsEnabled,
                        .notificationsDenied:
                    if let permissionState {
                        RequestPushNotificationsView(
                            isWaitingForInviteAcceptance: coordinator.isWaitingForInviteAcceptance,
                            permissionState: permissionState,
                            enableNotifications: {
                                Task {
                                    await coordinator.requestNotificationPermission()
                                }
                            },
                            openSettings: {
                                coordinator.openSettings()
                            }
                        )
                        .padding(.vertical, DesignConstants.Spacing.step4x)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
    }
}

#Preview("Setup Quickname - Not Dismissible") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .setupQuickname(autoDismiss: false)
    }
    .padding()
}

#Preview("Setup Quickname - Auto Dismiss") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .setupQuickname(autoDismiss: true)
    }
    .padding()
}

#Preview("Add Quickname") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .addQuickname(
            settings: QuicknameSettings.current(),
            profileImage: nil
        )
    }
    .padding()
}

#Preview("Save As Quickname") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()
    let sampleProfile = Profile(inboxId: "preview-inbox", name: "Jane Doe", avatar: nil)

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .saveAsQuickname(profile: sampleProfile)
    }
    .padding()
}

#Preview("Request Notifications") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .requestNotifications
    }
    .padding()
}

#Preview("Notifications Enabled") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .notificationsEnabled
    }
    .padding()
}

#Preview("Notifications Denied") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.state = .notificationsDenied
    }
    .padding()
}

#Preview("Waiting For Invite + Request Notifications") {
    @Previewable @State var coordinator = ConversationOnboardingCoordinator()

    ConversationOnboardingView(
        coordinator: coordinator,
        onTapSetupQuickname: { print("Tapped setup quickname") },
        onUseQuickname: { profile, _ in print("Use quickname: \(profile.displayName)") },
        onSaveAsQuickname: { _ in print("Save as quickname") }
    )
    .onAppear {
        coordinator.isWaitingForInviteAcceptance = true
        coordinator.state = .requestNotifications
    }
    .padding()
}
