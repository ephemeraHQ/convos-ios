import SwiftUI
import UIKit

class TypingIndicatorCollectionCell: UICollectionViewCell {
    func prepare(with alignment: Cell.Alignment) {
        contentConfiguration = UIHostingConfiguration {
            HStack {
                TypingIndicatorView(alignment: alignment)
                
                Spacer()
            }
        }
    }
}

struct TypingIndicatorView: View {
    let alignment: Cell.Alignment
    var body: some View {
        MessageContainer(style: .tailed,
                         isOutgoing: false) {
            ZStack {
                Text("")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12.0)
                    .font(.body)
                TypingIndicatorDots()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

        }
    }
}

struct TypingIndicatorDots: View {
    @State private var animate = false

    let dotCount = 3
    let dotSize: CGFloat = 10
    let dotSpacing: CGFloat = 6
    let animationDuration: Double = 0.6

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        Animation
                            .easeInOut(duration: animationDuration)
                            .repeatForever()
                            .delay(Double(index) * animationDuration / Double(dotCount)),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}


#Preview {
    TypingIndicatorView(alignment: .leading)
}
