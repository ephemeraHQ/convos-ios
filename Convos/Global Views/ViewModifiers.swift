import SwiftUI

struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}
