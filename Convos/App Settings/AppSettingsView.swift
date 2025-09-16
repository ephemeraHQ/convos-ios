import ConvosCore
import SwiftUI

struct ConvosToolbarButton: View {
    let padding: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: DesignConstants.Spacing.step2x) {
                Image("convosOrangeIcon")
                    .frame(width: 24.0, height: 24.0)

                Text("Convos")
                    .font(.system(size: 16.0, weight: .medium))
                    .foregroundStyle(.colorTextPrimary)
            }
            .padding(padding ? DesignConstants.Spacing.step2x : 0)
        }
    }
}

// swiftlint:disable force_unwrapping

struct AppSettingsView: View {
    let onDeleteAllInboxes: () -> Void
    @State private var showingDeleteAllDataConfirmation: Bool = false
    @Environment(\.openURL) private var openURL: OpenURLAction
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        openURL(URL(string: "https://xmtp.org")!)
                    } label: {
                        NavigationLink {
                            EmptyView()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 0.0) {
                                Text("Secured by ")
                                Image("xmtpIcon")
                                    .renderingMode(.template)
                                    .foregroundStyle(.colorTextPrimary)
                                    .padding(.trailing, 1.0)
                                Text("XMTP")
                            }
                            .foregroundStyle(.colorTextPrimary)
                        }
                    }
                    .foregroundStyle(.colorTextPrimary)

                    if !ConfigManager.shared.currentEnvironment.isProduction {
                        NavigationLink {
                            DebugExportView()
                        } label: {
                            Text("Debug")
                        }
                        .foregroundStyle(.colorTextPrimary)
                    }

                    Button {
                        openURL(URL(string: "https://convos.org/terms-and-privacy")!)
                    } label: {
                        NavigationLink("Privacy & Terms", destination: EmptyView())
                    }
                    .foregroundStyle(.colorTextPrimary)

                    Button {
                        sendFeedback()
                    } label: {
                        Text("Send feedback")
                    }
                    .foregroundStyle(.colorTextPrimary)
                } header: {
                    HStack {
                        Text("About")
                            .foregroundStyle(.colorTextSecondary)

                        Spacer()

                        Text("Version \(Bundle.appVersion)")
                            .font(.caption)
                            .foregroundStyle(.colorTextTertiary)
                    }
                } footer: {
                    Text("Made in the open by Ephemera")
                        .foregroundStyle(.colorTextSecondary)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteAllDataConfirmation = true
                    } label: {
                        Text("Delete all app data")
                    }
                    .confirmationDialog("", isPresented: $showingDeleteAllDataConfirmation) {
                        Button("Delete", role: .destructive) {
                            onDeleteAllInboxes()
                            dismiss()
                        }

                        Button("Cancel") {
                            showingDeleteAllDataConfirmation = false
                        }
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    ConvosToolbarButton(padding: true) {}
                        .glassEffect(.regular.tint(.colorBackgroundPrimary).interactive(), in: Capsule())
                        .disabled(true)
                }
            }
        }
    }

    private func sendFeedback() {
        let email = "convos@ephemerahq.com"
        let subject = "Convos Feedback"
        let mailtoString = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject)"

        if let mailtoURL = URL(string: mailtoString) {
            openURL(mailtoURL)
        }
    }
}

// swiftlint:enable force_unwrapping

#Preview {
    NavigationStack {
        AppSettingsView {}
    }
}
