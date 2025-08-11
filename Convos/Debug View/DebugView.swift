import SwiftUI

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
                        // Scroll to bottom when logs change
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("logs", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
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
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            refreshLogs()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshLogs() {
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let logContent = Logger.getLogs()
            DispatchQueue.main.async {
                self.logs = logContent
                self.isRefreshing = false
            }
        }
    }
}

struct DebugView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section {
                        HStack {
                            NavigationLink {
                                DebugLogsView()
                            } label: {
                                Text("Logs")
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Bundle ID")

                            Spacer()
                            Text(bundleIdentifier)
                                .foregroundStyle(.colorTextSecondary)
                        }
                        HStack {
                            Text("Version")

                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.colorTextSecondary)
                        }

                        HStack {
                            Text("Environment")

                            Spacer()
                            Text(ConfigManager.shared.currentEnvironment.rawValue.capitalized)
                                .foregroundStyle(.colorTextSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // share link
                }
            }
        }
    }

    private func generateTestLogs() {
        Logger.debug("🧪 This is a debug test message")
        Logger.info("🧪 This is an info test message")
        Logger.warning("🧪 This is a warning test message")
        Logger.error("🧪 This is an error test message")
    }
}

#Preview {
    DebugView()
}
