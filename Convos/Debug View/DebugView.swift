import ConvosCore
import SwiftUI
import UIKit

struct DebugLogsView: View {
    @State private var logs: String = ""
    @State private var isRefreshing: Bool = false
    @State private var timer: Timer?

    var body: some View {
        VStack {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(logs)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding()
                            .id("logs")
                    }
                    .onChange(of: logs) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("logs", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    let logsFile = FileManager.default.temporaryDirectory.appendingPathComponent("convos-debug-info.txt")
                    try? FileManager.default.removeItem(at: logsFile)
                    Logger.clearLogs {
                        refreshLogs()
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            refreshLogs()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshLogs()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshLogs() {
        isRefreshing = true
        Logger.getLogsAsync { logs in
            DispatchQueue.main.async {
                self.logs = logs
                self.isRefreshing = false
            }
        }
    }
}

struct DebugViewSection: View {
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationAuthGranted: Bool = false
    @State private var lastDeviceToken: String = ""
    @State private var debugFileURL: URL?
    @State private var preparingLogs: Bool = false

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    @MainActor
    private func prepareDebugInfoFile() async {
        guard !preparingLogs else { return }
        preparingLogs = true
        let logs = await Logger.getAllLogs()

        let debugInfo = """
        Convos Debug Information

        Bundle ID: \(bundleIdentifier)
        Version: \(Bundle.appVersion)
        Environment: \(ConfigManager.shared.currentEnvironment)

        \(logs)
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("convos-debug-info.txt")
        try? debugInfo.write(to: tempURL, atomically: true, encoding: .utf8)
        self.debugFileURL = tempURL
        self.preparingLogs = false
    }

    var body: some View {
        Group {
            Section(header: Text("Push Notifications")) {
                HStack {
                    Text("Auth Status")
                    Spacer()
                    Text(statusText(notificationAuthStatus))
                        .foregroundStyle(.colorTextSecondary)
                }
                HStack {
                    Text("Authorized")
                    Spacer()
                    Text(notificationAuthGranted ? "Yes" : "No")
                        .foregroundStyle(.colorTextSecondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device Token")
                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(lastDeviceToken)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.colorTextSecondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button {
                            UIPasteboard.general.string = lastDeviceToken
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .disabled(lastDeviceToken.isEmpty)
                    }
                }
                HStack {
                    Button("Request Now") {
                        Task { await requestNotificationsNow() }
                    }
                    .disabled(notificationAuthGranted)
                    .opacity(notificationAuthGranted ? 0.5 : 1.0)
                }
            }

            Section("Debug") {
                if let debugFileURL {
                    ShareLink(item: debugFileURL) {
                        HStack {
                            Text("Share logs")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(.colorTextPrimary)
                    }
                } else {
                    HStack {
                        Text("Preparing logs…")
                        Spacer()
                        if preparingLogs { ProgressView() }
                    }
                    .foregroundStyle(.colorTextSecondary)
                }

                HStack {
                    NavigationLink {
                        DebugLogsView()
                    } label: {
                        Text("View logs")
                    }
                }

                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text(bundleIdentifier)
                        .foregroundStyle(.colorTextSecondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.appVersion)
                        .foregroundStyle(.colorTextSecondary)
                }

                HStack {
                    Text("Environment")
                    Spacer()
                    Text(ConfigManager.shared.currentEnvironment.name.capitalized)
                        .foregroundStyle(.colorTextSecondary)
                }
            }
        }
        .task {
            await refreshNotificationStatus()
            await prepareDebugInfoFile()
        }
    }
}

#Preview {
    List {
        DebugViewSection()
    }
}

// MARK: - Push helpers

extension DebugViewSection {
    private func statusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthStatus = settings.authorizationStatus
        notificationAuthGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        lastDeviceToken = PushNotificationRegistrar.token ?? ""
    }

    private func requestNotificationsNow() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            await refreshNotificationStatus()
        } catch {
            Logger.error("Debug push request failed: \(error)")
        }
    }
}
