import SwiftUI

struct ThreePartContainerView<LeftContent: View, CenterContent: View, RightContent: View>: View {
    let leftContent: LeftContent
    let centerContent: CenterContent
    let rightContent: RightContent

    init(
        @ViewBuilder leftContent: () -> LeftContent,
        @ViewBuilder centerContent: () -> CenterContent,
        @ViewBuilder rightContent: () -> RightContent
    ) {
        self.leftContent = leftContent()
        self.centerContent = centerContent()
        self.rightContent = rightContent()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftContent
                .frame(maxHeight: .infinity, alignment: .top)
            centerContent
                .frame(maxHeight: .infinity, alignment: .center)
            rightContent
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Convenience Initializers

extension ThreePartContainerView where LeftContent == EmptyView {
    init(
        @ViewBuilder centerContent: () -> CenterContent,
        @ViewBuilder rightContent: () -> RightContent
    ) {
        self.leftContent = EmptyView()
        self.centerContent = centerContent()
        self.rightContent = rightContent()
    }
}

extension ThreePartContainerView where RightContent == EmptyView {
    init(
        @ViewBuilder leftContent: () -> LeftContent,
        @ViewBuilder centerContent: () -> CenterContent
    ) {
        self.leftContent = leftContent()
        self.centerContent = centerContent()
        self.rightContent = EmptyView()
    }
}

extension ThreePartContainerView where LeftContent == EmptyView, RightContent == EmptyView {
    init(
        @ViewBuilder centerContent: () -> CenterContent
    ) {
        self.leftContent = EmptyView()
        self.centerContent = centerContent()
        self.rightContent = EmptyView()
    }
}

// MARK: - Preview

#if DEBUG
struct ThreePartContainerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Full three-part layout
            ThreePartContainerView {
                Circle()
                    .fill(Color.red)
                    .overlay(Text("L"))
            } centerContent: {
                Rectangle()
                    .fill(Color.blue)
                    .overlay(Text("Center"))
            } rightContent: {
                Circle()
                    .fill(Color.green)
                    .overlay(Text("R"))
            }
            .frame(height: 60)
            .padding()

            // Left and center only
            ThreePartContainerView {
                Circle()
                    .fill(Color.red)
                    .overlay(Text("L"))
                    .frame(height: 60)
            } centerContent: {
                Rectangle()
                    .fill(Color.blue)
                    .overlay(Text("Center"))
                    .frame(height: 30)
            }
            .padding()

            // Center and right only
            ThreePartContainerView {
                Rectangle()
                    .fill(Color.blue)
                    .overlay(Text("Center"))
            } rightContent: {
                Circle()
                    .fill(Color.green)
                    .overlay(Text("R"))
                    .frame(height: 60.0)
            }
            .padding()

            // Center only
            ThreePartContainerView {
                Rectangle()
                    .fill(Color.blue)
                    .overlay(Text("Center Only"))
                    .frame(height: 60)
            }
            .padding()

            Spacer()
        }
    }
}
#endif
