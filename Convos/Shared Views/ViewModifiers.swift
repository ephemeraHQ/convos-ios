import SwiftUI

// MARK: - Height Reading

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

extension View {
    func readHeight(onChange: @escaping (CGFloat) -> Void) -> some View {
        self
            .background(HeightReader())
            .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

// MARK: - Width Reading

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
        }
    }
}

extension View {
    func readWidth(onChange: @escaping (CGFloat) -> Void) -> some View {
        self
            .background(WidthReader())
            .onPreferenceChange(WidthPreferenceKey.self, perform: onChange)
    }
}
