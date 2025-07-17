import Foundation
import SwiftUI

/// Helper for previewing any UIView in SwiftUI
struct UIViewPreview<View: UIView>: UIViewRepresentable {
    let viewBuilder: () -> View
    init(_ builder: @escaping () -> View) { self.viewBuilder = builder }
    func makeUIView(context: Context) -> View { viewBuilder() }
    func updateUIView(_ uiView: View, context: Context) {}
}
