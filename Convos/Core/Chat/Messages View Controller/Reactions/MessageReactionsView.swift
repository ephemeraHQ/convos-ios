import SwiftUI

struct MessageReactionsView: View {
    let viewModel: MessageReactionMenuViewModelType
    let padding: CGFloat = 8.0
    let emojiAppearanceDelay: TimeInterval = 0.3

    // Animation states
    @State private var emojiAppeared: [Bool] = []
    @State private var showMoreAppeared: Bool = false
    @State private var didAppear: Bool = false

    var body: some View {
        HStack {
            GeometryReader { reader in
                let contentHeight = reader.size.height - (padding * 2.0)
                ZStack {
                    ScrollView(.horizontal,
                               showsIndicators: false) {
                        HStack(spacing: 0.0) {
                            ForEach(Array(viewModel.reactions.enumerated()), id: \ .element.id) { index, reaction in
                                Button {
                                    viewModel.add(reaction: reaction)
                                } label: {
                                    Text(reaction.emoji)
                                        .font(.system(size: 24.0))
                                        .padding(padding)
                                        .scaleEffect(
                                            emojiAppeared.indices.contains(index) &&
                                            emojiAppeared[index] ? 1.0 : 0.0
                                        )
                                        .rotationEffect(
                                            .degrees(
                                                emojiAppeared.indices.contains(index) &&
                                                emojiAppeared[index] ? 0 : -15
                                            )
                                        )
                                        .animation(
                                            .spring(response: 0.4,
                                                    dampingFraction: 0.6),
                                            value: emojiAppeared.indices.contains(index) ? emojiAppeared[index] : false
                                        )
                                }
                                .onAppear {
                                    // Staggered animation
                                    if emojiAppeared.indices.contains(index) && !emojiAppeared[index] {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + emojiAppearanceDelay + 0.08 * Double(index)) {
                                            withAnimation {
                                                emojiAppeared[index] = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, padding)
                    }.frame(height: reader.size.height)
                        .contentMargins(.trailing, contentHeight, for: .scrollContent)
                        .mask(
                            HStack(spacing: 0) {
                                // Left gradient
                                LinearGradient(gradient:
                                                Gradient(
                                                    colors: [Color.black.opacity(0), Color.black]),
                                               startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: padding)
                                // Middle
                                Rectangle().fill(Color.black)
                                // Right gradient
                                LinearGradient(gradient:
                                                Gradient(
                                                    colors: [Color.black, Color.black.opacity(0)]),
                                               startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: (contentHeight * 0.3))
                                // Right button area
                                Rectangle().fill(Color.clear)
                                    .frame(width: contentHeight)
                            }
                        )
                    HStack(spacing: padding) {
                        Spacer()
                        Button {
                            viewModel.showMoreReactions()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24.0))
                                .padding(padding)
                                .tint(.colorTextSecondary)
                                .offset(x: showMoreAppeared ? 0 : 40)
                                .opacity(showMoreAppeared ? 1 : 0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showMoreAppeared)
                        }
                        .frame(minWidth: contentHeight)
                        .padding(.trailing, padding)
                    }
                    .background(.clear)
                }
            }
            .padding(0.0)
            .onAppear {
                guard !didAppear else { return }

                didAppear = true

                if emojiAppeared.count != viewModel.reactions.count {
                    emojiAppeared = Array(repeating: false, count: viewModel.reactions.count)
                }

                let totalDelay = emojiAppearanceDelay + 0.08 * Double(viewModel.reactions.count)
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                    withAnimation {
                        showMoreAppeared = true
                    }
                }
            }
        }
    }
}

#Preview {
    MessageReactionsView(viewModel: MessageReactionMenuViewModel())
        .frame(width: 280.0, height: 56.0)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
}
