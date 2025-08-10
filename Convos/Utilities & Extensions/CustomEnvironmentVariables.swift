import SwiftUI

// MARK: - Safe Area Insets Environment Value

private struct SafeAreaInsetsEnvironmentKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = EdgeInsets()
}

public extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsEnvironmentKey.self] }
        set { self[SafeAreaInsetsEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Modifier to inject safe area insets into environment

private struct SafeAreaEnvironmentModifier: ViewModifier {
    @State private var currentInsets: EdgeInsets = EdgeInsets()

    func body(content: Content) -> some View {
        content
            .environment(\.safeAreaInsets, currentInsets)
            .onAppear {
                // Get safe area insets from the window when the view appears
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    currentInsets = EdgeInsets(
                        top: window.safeAreaInsets.top,
                        leading: window.safeAreaInsets.left,
                        bottom: window.safeAreaInsets.bottom,
                        trailing: window.safeAreaInsets.right
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Update insets when orientation changes
                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        currentInsets = EdgeInsets(
                            top: window.safeAreaInsets.top,
                            leading: window.safeAreaInsets.left,
                            bottom: window.safeAreaInsets.bottom,
                            trailing: window.safeAreaInsets.right
                        )
                    }
                }
            }
    }
}

public extension View {
    /// Injects an environment value `safeAreaInsets` that mirrors the system safe area insets
    /// so any descendant can access it via `@Environment(\.safeAreaInsets)`.
    func withSafeAreaEnvironment() -> some View {
        modifier(SafeAreaEnvironmentModifier())
    }
}
