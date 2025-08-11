import Combine
import SwiftUI

/// Debug error presenter that shows errors as overlays in development builds
@MainActor
final class DebugErrorPresenter: ObservableObject {
    static let shared: DebugErrorPresenter = DebugErrorPresenter()

    @Published var currentError: DebugError?
    @Published var errorHistory: [DebugError] = []

    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()

    private init() {
        setupErrorCapture()
    }

    struct DebugError: Identifiable, Equatable {
        let id: UUID = UUID()
        let timestamp: Date = Date()
        let title: String
        let message: String
        let details: String?
        let file: String
        let function: String
        let line: Int

        var formattedLocation: String {
            "\(file.split(separator: "/").last ?? ""):\(line)"
        }
    }

    func presentError(
        _ error: Error,
        title: String = "Error",
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        guard ConfigManager.shared.currentEnvironment.shouldShowDebugErrors else { return }

        let debugError = DebugError(
            title: title,
            message: error.localizedDescription,
            details: details ?? String(describing: error),
            file: file,
            function: function,
            line: line
        )

        currentError = debugError
        errorHistory.append(debugError)

        // Auto-dismiss after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.currentError?.id == debugError.id {
                self?.currentError = nil
            }
        }

        Logger.error("🚨 [\(debugError.formattedLocation)] \(title): \(error)")
        #endif
    }

    func dismiss() {
        currentError = nil
    }

    func clearHistory() {
        errorHistory.removeAll()
    }

    private func setupErrorCapture() {
        // Subscribe to API errors
        NotificationCenter.default.publisher(for: .apiError)
            .compactMap { $0.object as? Error }
            .sink { [weak self] error in
                self?.presentError(error, title: "API Error")
            }
            .store(in: &cancellables)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let apiError: Notification.Name = Notification.Name("convos.api.error")
}

// MARK: - Debug Error View

struct DebugErrorOverlay: View {
    @ObservedObject private var presenter: DebugErrorPresenter = DebugErrorPresenter.shared
    @State private var isExpanded: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if let error = presenter.currentError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text(error.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            Text(error.message)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(isExpanded ? nil : 2)
                        }

                        Spacer()

                        Button(action: { presenter.dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location: \(error.formattedLocation)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))

                            if let details = error.details {
                                ScrollView {
                                    Text(details)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 100)
                            }

                            HStack {
                                Button("Copy") {
                                    UIPasteboard.general.string = error.details ?? error.message
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(4)

                                Button("Report") {
                                    // Could open GitHub issue or send to logging service
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.9))
                        .shadow(radius: 10)
                )
                .padding(.horizontal)
                .padding(.top, 50)
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(presenter.currentError != nil)
        .animation(.spring(), value: presenter.currentError)
    }
}

// MARK: - Shake Gesture Debug Console

struct ShakeDebugConsole: ViewModifier {
    @State private var showingDebugConsole: Bool = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                #if DEBUG
                if ConfigManager.shared.currentEnvironment.shouldShowDebugErrors {
                    showingDebugConsole = true
                }
                #endif
            }
            .sheet(isPresented: $showingDebugConsole) {
                DebugConsoleView()
            }
    }
}

struct DebugConsoleView: View {
    @ObservedObject private var presenter: DebugErrorPresenter = DebugErrorPresenter.shared
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationView {
            List {
                Section("Recent Errors (\(presenter.errorHistory.count))") {
                    ForEach(presenter.errorHistory.reversed()) { error in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(error.title)
                                    .font(.headline)
                                Spacer()
                                Text(error.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(error.message)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(error.formattedLocation)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Debug Actions") {
                    Button("Clear Error History") {
                        presenter.clearHistory()
                    }

                    Button("Test Error") {
                        presenter.presentError(
                            NSError(domain: "TestError", code: 123, userInfo: [
                                NSLocalizedDescriptionKey: "This is a test error"
                            ]),
                            title: "Test Error"
                        )
                    }
                }
            }
            .navigationTitle("Debug Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Shake Detection

extension Notification.Name {
    static let deviceDidShake: Notification.Name = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

// MARK: - View Extension

extension View {
    func withDebugErrorHandling() -> some View {
        self
            .overlay(DebugErrorOverlay())
            .modifier(ShakeDebugConsole())
    }
}
