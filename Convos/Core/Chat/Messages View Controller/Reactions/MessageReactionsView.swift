import SwiftUI

struct MessageReactionsView: View {
    @State var viewModel: MessageReactionMenuViewModel
    let padding: CGFloat = 8.0
    let emojiAppearanceDelay: TimeInterval = 0.3

    init(viewModel: MessageReactionMenuViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    @State private var emojiAppeared: [Bool] = []
    @State private var showMoreAppeared: Bool = false
    @State private var didAppear: Bool = false

    var body: some View {
        Group {
            GeometryReader { reader in
                let contentHeight = reader.size.height - (padding * 2.0)
                ZStack(alignment: .leading) {
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
                                        .blur(
                                            radius: (viewModel.isCollapsed ? 10.0 :
                                                        emojiAppeared.indices.contains(index)
                                                     && emojiAppeared[index] ? 0.0 : 10.0)
                                        )
                                        .scaleEffect(
                                            viewModel.isCollapsed ? 0.0 : (emojiAppeared.indices.contains(index) &&
                                                                 emojiAppeared[index] ? 1.0 : 0.0)
                                        )
                                        .rotationEffect(
                                            .degrees(
                                                emojiAppeared.indices.contains(index) && emojiAppeared[index] ? 0 : -15
                                            )
                                        )
                                        .opacity(viewModel.isCollapsed ? 0 : 1)
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.6),
                                            value: viewModel.isCollapsed
                                        )
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.6),
                                            value: emojiAppeared.indices.contains(index) ? emojiAppeared[index] : false
                                        )
                                }
                                .onAppear {
                                    // Staggered animation
                                    if emojiAppeared.indices.contains(index) && !emojiAppeared[index] {
                                        DispatchQueue.main.asyncAfter(
                                            deadline: .now() + emojiAppearanceDelay + 0.08 * Double(index)
                                        ) {
                                            withAnimation {
                                                emojiAppeared[index] = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, padding)
                    }
                    .frame(height: reader.size.height)
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

                    HStack(spacing: 0.0) {
                        if !viewModel.isCollapsed {
                            Spacer()
                        }

                        Image(systemName: "face.smiling")
                            .font(.system(size: 28.0))
                            .padding(padding)
                            .tint(.black)
                            .opacity(viewModel.isCollapsed ? 0.2 : 0.0)
                            .blur(radius: viewModel.isCollapsed ? 0.0 : 10.0)
                            .rotationEffect(
                                .degrees(
                                    viewModel.isCollapsed ? 0.0 : -30.0
                                )
                            )
                            .scaleEffect(
                                viewModel.isCollapsed ? 1.0 : 0.0
                            )
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isCollapsed)
                            .padding(.horizontal, padding)

                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                viewModel.toggleCollapsed()
                            }
                            viewModel.showMoreReactions()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24.0))
                                .padding(padding)
                                .tint(.colorTextSecondary)
                                .offset(x: showMoreAppeared ? 0 : 40)
                                .opacity(showMoreAppeared ? 1 : 0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showMoreAppeared)
                                .rotationEffect(
                                    .degrees(
                                        viewModel.isCollapsed ? -45.0 : 0.0
                                    )
                                )
                        }
                        .frame(minWidth: contentHeight)
                        .padding(.trailing, 8.0)
                    }
                }
            }
            .padding(0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isCollapsed)
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
