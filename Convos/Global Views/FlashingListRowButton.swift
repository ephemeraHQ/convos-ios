import SwiftUI

struct FlashingListRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }

            // Optional delay to show flash before navigating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPressed = false
                }
                action()
            }
        }) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12) // default spacing, can be overridden by content
                .background(
                    Color.gray.opacity(isPressed ? 0.2 : 0.0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
