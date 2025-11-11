import SwiftUI

/// A generic animated overlay view that handles fade-in/scale animations and optional auto-dismiss
struct AnimatedOverlayView<Content: View>: View {
    let autoDismiss: Bool
    let duration: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let content: (_ animateOut: @escaping () -> Void) -> Content

    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0.0
    @State private var blur: CGFloat = 10.0

    init(
        autoDismiss: Bool = true,
        duration: CGFloat = 8.0,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (_ animateOut: @escaping () -> Void) -> Content
    ) {
        self.autoDismiss = autoDismiss
        self.duration = duration
        self.onDismiss = onDismiss
        self.content = content
    }

    func animateIn() {
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            scale = 1.0
            opacity = 1.0
            blur = 0.0
        }
    }

    func animateOut() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.15
            opacity = 0.0
            blur = 10.0
        }
    }

    var body: some View {
        content(animateOut)
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blur)
            .onAppear {
                animateIn()
            }
            .task {
                if autoDismiss {
                    try? await Task.sleep(for: .seconds(duration))
                    animateOut()
                    onDismiss()
                }
            }
    }
}

#Preview {
    AnimatedOverlayView(
        autoDismiss: true,
        duration: 3.0,
        onDismiss: {},
        content: { animateOut in
            Button {
                animateOut()
            } label: {
                Text("Hello, World!")
                    .padding()
                    .background(Capsule().fill(.blue))
                    .foregroundStyle(.white)
            }
        }
    )
}
