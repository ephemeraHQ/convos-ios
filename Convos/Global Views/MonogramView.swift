import SwiftUI

struct MonogramView: View {
    private let initials: String
    private let backgroundColor: Color

    init(name: String) {
        self.initials = Self.initials(from: name)
        self.backgroundColor = Self.colorForName(name)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let fontSize = side * 0.5
            let padding = side * 0.25

            Group {
                Text(initials)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(padding)
            }
            .frame(width: side, height: side)
            .background(backgroundColor)
            .clipShape(Circle())
        }
        .aspectRatio(1.0, contentMode: .fit)
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
    VStack {
        MonogramView(name: "Robert Adams")
            .frame(width: 24.0)
        MonogramView(name: "Robert Adams")
            .frame(width: 36.0)
        MonogramView(name: "Robert Adams")
            .frame(width: 52.0)
        MonogramView(name: "Robert Adams")
            .frame(width: 96.0)
    }
}
