import SwiftUI

struct MessageReactionsView: View {
    let viewModel: MessageReactionMenuViewModelType
    let padding: CGFloat = 8.0

    var body: some View {
        HStack {
            GeometryReader { reader in
                let contentHeight = reader.size.height - (padding * 2.0)
                ZStack {
                    ScrollView(.horizontal,
                               showsIndicators: false) {
                        HStack(spacing: 0.0) {
                            ForEach(viewModel.reactions) { reaction in
                                Button {
                                    viewModel.add(reaction: reaction)
                                } label: {
                                    Text(reaction.emoji)
                                        .font(.system(size: 24.0))
                                        .padding(padding)
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
                        }
                        .frame(minWidth: contentHeight)
                        .padding(.trailing, padding)
                    }
                    .background(.clear)
                }
            }
            .padding(0.0)
        }
    }
}

#Preview {
    MessageReactionsView(viewModel: MessageReactionMenuViewModel())
        .frame(width: 280.0, height: 56.0)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
}
