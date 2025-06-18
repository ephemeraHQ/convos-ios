import SwiftUI

struct CustomToolbarView<Content: View>: View {
    let onBack: () -> Void
    let rightContent: Content
    let showBackText: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?

    init(
        onBack: @escaping () -> Void,
        showBackText: Bool = true,
        @ViewBuilder rightContent: () -> Content
    ) {
        self.onBack = onBack
        self.showBackText = showBackText
        self.rightContent = rightContent()
    }

    var backButtonVerticalPadding: CGFloat {
        verticalSizeClass == .compact ?
        DesignConstants.Spacing.step2x :
        DesignConstants.Spacing.step4x
    }

    var backButtonHorizontalPadding: CGFloat {
        showBackText ? DesignConstants.Spacing.step4x : DesignConstants.Spacing.step2x
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
                .padding(.horizontal, backButtonHorizontalPadding)
            }
            .padding(.trailing, 2.0)

            Spacer()

            rightContent
        }
        .frame(height: 72.0)
        .padding(.leading, DesignConstants.Spacing.step2x)
        .padding(.trailing, DesignConstants.Spacing.step2x)
        .background(.colorBackgroundPrimary)
    }
}

#Preview("With Back Text") {
    VStack(spacing: 20) {
        CustomToolbarView(onBack: {}, rightContent: {
            // Empty right content
        })

        Spacer()
    }
}

#Preview("Without Back Text") {
    VStack(spacing: 20) {
        CustomToolbarView(onBack: {}, showBackText: false, rightContent: {
            // Empty right content
        })

        Spacer()
    }
}

#Preview("With Right Buttons") {
    VStack(spacing: 20) {
        CustomToolbarView(onBack: {}, rightContent: {
            HStack {
                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }

                Button {
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
            }
        })

        Spacer()
    }
}
