import SwiftUI

struct MessageReactionsView: View {
    @State var viewModel: MessageReactionMenuViewModel
    let padding: CGFloat = 8.0
    let emojiAppearanceDelay: TimeInterval = 0.4
    let emojiAppearanceDelayStep: TimeInterval = 0.05

    init(viewModel: MessageReactionMenuViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    @State private var emojiAppeared: [Bool] = []
    @State private var showMoreAppeared: Bool = false
    @State private var didAppear: Bool = false
    @State private var customEmoji: String?
    @State private var popScale: CGFloat = 1.0

    var body: some View {
        Group {
            GeometryReader { reader in
                let contentHeight = max(reader.size.height - (padding * 2.0), 0.0)
                ZStack(alignment: .leading) {
                    ScrollView(.horizontal,
                               showsIndicators: false) {
                        HStack(spacing: 0.0) {
                            ForEach(Array(viewModel.reactions.enumerated()),
                                    id: \ .element.id) { index, reaction in
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
                                .scaleEffect(
                                    (viewModel.selectedEmoji == nil ? 1.0 : 0.0)
                                )
                                .onAppear {
                                    // Staggered animation
                                    if emojiAppeared.indices.contains(index) && !emojiAppeared[index] {
                                        DispatchQueue.main.asyncAfter(
                                            deadline: (.now() + emojiAppearanceDelay +
                                                       (emojiAppearanceDelayStep * Double(index)))
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
                               .animation(
                                .spring(response: 0.4, dampingFraction: 0.8),
                                value: viewModel.isCollapsed
                               )

                    HStack(spacing: 0.0) {
                        Spacer()

                        ZStack {
                            Text(viewModel.selectedEmoji ?? customEmoji ?? "")
                                .multilineTextAlignment(.center)
                                .font(.system(size: 28.0))
                                .frame(width: 32.0, height: 32.0)
                                .scaleEffect(
                                    popScale *
                                    (
                                        (viewModel.isCollapsed && customEmoji != nil) ||
                                        viewModel.selectedEmoji != nil ? 1.0 : 0.0
                                    )
                                )
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: customEmoji)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.selectedEmoji)
                                .onChange(of: viewModel.selectedEmoji ?? customEmoji ?? "") {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                        popScale = 1.2
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            popScale = 1.0
                                        }
                                    }
                                }

                            Image(systemName: "face.smiling")
                                .font(.system(size: 28.0))
                                .tint(.black)
                                .opacity(viewModel.isCollapsed ? 0.2 : 0.0)
                                .blur(radius: viewModel.isCollapsed ? 0.0 : 10.0)
                                .rotationEffect(
                                    .degrees(
                                        viewModel.isCollapsed ? 0.0 : -30.0
                                    )
                                )
                                .scaleEffect(
                                    viewModel.isCollapsed &&
                                    customEmoji == nil &&
                                    viewModel.selectedEmoji == nil ? 1.0 : 0.0
                                )
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8),
                                    value: viewModel.isCollapsed
                                )
                        }
                        .frame(width: reader.size.height, height: reader.size.height)

                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                viewModel.toggleCollapsed()
                            }
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
                        .scaleEffect(
                            viewModel.selectedEmoji == nil ? 1.0 : 0.0
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isCollapsed)
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
                let totalDelay = emojiAppearanceDelay + (emojiAppearanceDelayStep * Double(viewModel.reactions.count))
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                    withAnimation {
                        showMoreAppeared = true
                    }
                }
            }
        }
        .emojiPicker(isPresented: $viewModel.showingEmojiPicker,
                     onPick: { emoji in
            customEmoji = emoji
            viewModel.add(reaction: .init(id: "7", emoji: emoji, isSelected: true))
        }, onDelete: {
            customEmoji = nil
        })
    }
}

#Preview {
    MessageReactionsView(viewModel: MessageReactionMenuViewModel())
        .frame(width: 280.0, height: 56.0)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
}
