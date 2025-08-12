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

    private var debugInfoFileURL: URL {
        let logs = Logger.getLogs()

        // Create debug info text
        let debugInfo = """
        Convos Debug Information

        Bundle ID: \(bundleIdentifier)
        Version: \(appVersion)
        Environment: \(ConfigManager.shared.currentEnvironment)

        Logs:
        \(logs)
        """

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("convos-debug-info.txt")

        try? debugInfo.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
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
                                Text("View logs")
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
                    ShareLink(item: debugInfoFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

#Preview {
    DebugView()
}
