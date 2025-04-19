import SwiftUI

struct MonogramView: View {
    private let initials: String
    private let backgroundColor: Color

    init(name: String) {
        self.initials = Self.initials(from: name)
        self.backgroundColor = Self.colorForName(name)
    }

    var body: some View {
        GeometryReader { reader in
            Text(initials)
                .font(.system(size: reader.size.width * 0.3, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: reader.size.width, height: reader.size.height)
                .background(backgroundColor)
                .clipShape(Circle())
        }
    }

    private static func initials(from fullName: String) -> String {
        let components = fullName.split(separator: " ")
        let initials = components.prefix(2).map { $0.first.map(String.init) ?? "" }
        return initials.joined().uppercased()
    }

    private static func colorForName(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal, .indigo]
        let hash = name.hashValue
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

#Preview {
    MonogramView(name: "Robert Adams")
        .frame(width: 96.0, height: 96.0)
}
