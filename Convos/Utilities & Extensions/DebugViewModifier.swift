import SwiftUI

struct DebugViewModifier: ViewModifier {
    let identifier: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                Logger.info("🎯 View appeared: \(identifier)")
            }
            .onDisappear {
                Logger.info("🎯 View disappeared: \(identifier)")
            }
    }
}

extension View {
    func debugView(_ identifier: String) -> some View {
        modifier(DebugViewModifier(identifier: identifier))
    }
}
