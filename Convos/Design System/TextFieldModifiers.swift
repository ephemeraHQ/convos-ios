import SwiftUI

struct CharacterLimitModifier: ViewModifier {
    @Binding var text: String
    let limit: Int

    func body(content: Content) -> some View {
        content
            .onChange(of: text) { _, newValue in
                if newValue.count > limit {
                    text = String(newValue.prefix(limit))
                }
            }
    }
}

extension View {
    func characterLimit(_ limit: Int, text: Binding<String>) -> some View {
        modifier(CharacterLimitModifier(text: text, limit: limit))
    }
}
