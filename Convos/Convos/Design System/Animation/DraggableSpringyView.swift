//
//  DraggableSpringyView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/17/25.
//

import SwiftUI
import UIKit

struct DraggableSpringyView<Content: View>: View {
    let content: () -> Content
    var maxDragDistance: CGFloat
    var springStiffness: CGFloat
    var springDamping: CGFloat

    @State private var dragOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    @State private var isDragging = false

    init(
        maxDragDistance: CGFloat = 100.0,
        springStiffness: CGFloat = 200.0,
        springDamping: CGFloat = 20.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxDragDistance = maxDragDistance
        self.springStiffness = springStiffness
        self.springDamping = springDamping
        self.content = content
    }

    var body: some View {
        let dragGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isDragging {
                    isDragging = true
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            .updating($gestureOffset) { value, state, _ in
                state = elasticOffset(for: value.translation)
            }
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.interpolatingSpring(stiffness: springStiffness, damping: springDamping)) {
                    dragOffset = .zero
                }
                isDragging = false
            }

        let totalOffset = CGSize(
            width: dragOffset.width + gestureOffset.width,
            height: dragOffset.height + gestureOffset.height
        )

        let rotationAmount = Angle(degrees: Double(totalOffset.width) / 10)
        let scaleAmount = 1.0 - (min(abs(totalOffset.width), maxDragDistance) / maxDragDistance) * 0.05

        return content()
            .scaleEffect(isDragging ? scaleAmount : 1.0)
            .rotationEffect(rotationAmount)
            .offset(totalOffset)
            .simultaneousGesture(dragGesture)
            .animation(.interpolatingSpring(stiffness: springStiffness, damping: springDamping), value: totalOffset)
    }

    private func elasticOffset(for translation: CGSize) -> CGSize {
        CGSize(
            width: rubberClamp(translation.width),
            height: rubberClamp(translation.height)
        )
    }

    private func rubberClamp(_ value: CGFloat) -> CGFloat {
        let sign = value >= 0 ? 1.0 : -1.0
        let absValue = abs(value)
        let clamped = maxDragDistance * (1 - pow(2, -absValue / (maxDragDistance / 2)))
        return sign * min(clamped, maxDragDistance * 1.5)
    }
}
