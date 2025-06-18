import SwiftUI

enum CustomToolbarConstants {
    static let regularHeight: CGFloat = 72.0
    static let compactHeight: CGFloat = 52.0
}

struct CustomToolbarView<Content: View>: View {
    let onBack: () -> Void
    let rightContent: Content
    let showBackText: Bool
    let showBottomBorder: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?

    init(
        onBack: @escaping () -> Void,
        showBackText: Bool = true,
        showBottomBorder: Bool = false,
        @ViewBuilder rightContent: () -> Content
    ) {
        self.onBack = onBack
        self.showBackText = showBackText
        self.showBottomBorder = showBottomBorder
        self.rightContent = rightContent()
    }

    var barHeight: CGFloat {
        verticalSizeClass == .compact ? CustomToolbarConstants.compactHeight : CustomToolbarConstants.regularHeight
    }

    var backButtonVerticalPadding: CGFloat {
        verticalSizeClass == .compact ?
        DesignConstants.Spacing.step2x :
        DesignConstants.Spacing.step4x
    }

    var body: some View {
        HStack(spacing: 0.0) {
            Button(action: onBack) {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24.0))

                    if showBackText {
                        Text("Back")
                            .font(.system(size: 16.0))
                            .padding(.leading, DesignConstants.Spacing.step4x)
                    }
                }
                .foregroundStyle(.colorTextPrimary)
                .padding(.vertical, backButtonVerticalPadding)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
            .padding(.trailing, 2.0)

            Spacer()

            rightContent
        }
        .frame(height: barHeight)
        .padding(.leading, DesignConstants.Spacing.step4x)
        .padding(.trailing, DesignConstants.Spacing.step2x)
        .background(.colorBackgroundPrimary)
        .overlay(alignment: .bottom) {
            if showBottomBorder {
                Rectangle()
                    .fill(.colorBorderSubtle2)
                    .frame(height: 1.0)
            }
        }
    }
}

#Preview() {
    VStack(spacing: 0) {
        // With Back Text
        CustomToolbarView(onBack: {}, rightContent: {
            EmptyView()
        })

        // Without Back Text (chevron only)
        CustomToolbarView(onBack: {}, showBackText: false, rightContent: {
            EmptyView()
        })

        // New Chat state (no back text, with title and border)
        CustomToolbarView(onBack: {}, showBackText: false, showBottomBorder: true, rightContent: {
            HStack(spacing: 0) {
                Text("New chat")
                    .font(.system(size: 16.0))
                    .foregroundStyle(.colorTextPrimary)
                    .lineLimit(1)

                Spacer()
            }
        })

        // With conversation title and avatar simulation (no border)
        CustomToolbarView(onBack: {}, showBackText: false, rightContent: {
            HStack(spacing: 0) {
                Button(action: {}, label: {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 32, height: 32)
                            .padding(.vertical, DesignConstants.Spacing.step4x)

                        VStack(alignment: .leading, spacing: 2.0) {
                            Text("John Doe")
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)
                                .lineLimit(1)
                        }
                        .padding(.leading, DesignConstants.Spacing.step2x)
                    }
                })
                .buttonStyle(PlainButtonStyle())

                Spacer()

                // Right side button
                Button(action: {}, label: {
                    Image(systemName: "timer")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step4x)
                })
            }
        })

        Spacer()
    }
}
