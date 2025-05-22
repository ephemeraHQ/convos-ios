import SwiftUI

struct FlashingListRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPressed = false
                }
                action()
            }
        } label: {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, DesignConstants.Spacing.step3x)
                .background(
                    Color.gray.opacity(isPressed ? 0.2 : 0.0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
