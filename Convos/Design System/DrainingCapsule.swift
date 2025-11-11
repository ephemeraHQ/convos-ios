import SwiftUI

struct DrainingCapsule: View {
    let fillColor: Color
    let backgroundColor: Color
    let duration: TimeInterval

    @State private var progress: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            // Background
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(backgroundColor)
                Rectangle()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * progress)
            }
            .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 0.0
            }
        }
    }
}

#Preview {
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        DrainingCapsule(
            fillColor: .blue,
            backgroundColor: .gray.opacity(0.3),
            duration: 3.0
        )
        .frame(height: 8)
        .id(resetId)

        DrainingCapsule(
            fillColor: .colorBackgroundInverted,
            backgroundColor: .colorFillTertiary,
            duration: 5.0
        )
        .frame(height: 12)
        .id(resetId)

        DrainingCapsule(
            fillColor: .green,
            backgroundColor: .red.opacity(0.2),
            duration: 2.0
        )
        .frame(height: 20)
        .id(resetId)

        Button("Repeat") {
            resetId = UUID()
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 20)
    }
    .padding()
}
