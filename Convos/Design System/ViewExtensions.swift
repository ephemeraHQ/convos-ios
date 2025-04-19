import Foundation
import SwiftUI

// MARK: Helpers

extension View {
    @ViewBuilder
    func applyIf(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: LabeledContentStyles

struct VerticalLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
            configuration.content
        }
    }
}

extension LabeledContentStyle where Self == VerticalLabeledContentStyle {
    static var vertical: VerticalLabeledContentStyle { .init() }
}
