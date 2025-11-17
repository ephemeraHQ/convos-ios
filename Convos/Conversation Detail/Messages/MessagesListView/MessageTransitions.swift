import ConvosCore
import SwiftUI

// MARK: - Message Transition Modifier

struct MessageTransitionModifier: ViewModifier {
    let source: MessageSource
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 0.9 : 1.0)
            .rotationEffect(
                isActive
                ? .radians(source == .incoming ? -0.05 : 0.05)
                : .radians(0)
            )
            .offset(
                x: isActive
                ? (source == .incoming ? -20 : 20)
                : 0,
                y: isActive ? 40 : 0
            )
            .opacity(isActive ? 0 : 1)
    }
}

// MARK: - AnyTransition Extension

extension AnyTransition {
    static func message(source: MessageSource) -> AnyTransition {
        .modifier(
            active: MessageTransitionModifier(source: source, isActive: true),
            identity: MessageTransitionModifier(source: source, isActive: false)
        )
    }
}

// MARK: - Additional Message Transitions

extension AnyTransition {
    /// Transition for sent status indicators
    static var sentIndicator: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)),
            removal: .opacity
        )
    }

    /// Transition for typing indicators
    static var typingIndicator: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.8))
        )
    }

    /// Transition for date separators
    static var dateSeparator: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.9, anchor: .center))
    }
}
