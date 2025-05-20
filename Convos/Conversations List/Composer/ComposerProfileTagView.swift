import SwiftUI

private struct SelectionBarOverlay: View {
    let color: Color = .black
    private let circleSize: CGFloat = 14.0
    private let barWidth: CGFloat = 2.0

    var body: some View {
        ZStack {
            HStack {
                selectionBarLeft
                Spacer()
                selectionBarRight
            }

            HStack {
                Rectangle().fill(color)
                    .frame(width: barWidth)
                Spacer()
                Rectangle().fill(color)
                    .frame(width: barWidth)
            }
        }
    }

    var selectionBarLeft: some View {
        VStack(spacing: 0.0) {
            Circle().fill(color)
                .frame(width: circleSize, height: circleSize)
            Spacer()
        }
        .offset(x: -(circleSize / 2.0) + (barWidth / 2.0),
                y: -circleSize * 0.75)
    }

    var selectionBarRight: some View {
        VStack(spacing: 0.0) {
            Spacer()
            Circle().fill(color)
                .frame(width: circleSize, height: circleSize)
        }
        .offset(x: (circleSize / 2.0) - (barWidth / 2.0),
                y: circleSize * 0.75)
    }
}

#Preview {
    SelectionBarOverlay()
}

struct ComposerProfileTagView: View {
    let profile: Profile
    var isSelected: Bool

    var body: some View {
        HStack {
            HStack(spacing: DesignConstants.Spacing.stepX) {
                ProfileAvatarView(profile: profile, size: DesignConstants.ImageSizes.extraSmallAvatar)
                Text(profile.displayName)
                    .font(.system(size: 16.0))
                    .foregroundStyle(.colorTextPrimary)
                    .padding(.vertical, DesignConstants.Spacing.step2x)
            }
            .padding(.horizontal, 10.0)
        }
        .overlay(
            Group {
                if isSelected {
                    SelectionBarOverlay()
                }
            }
        )
        .zIndex(isSelected ? 100 : 0)
        .background(
            RoundedRectangle(cornerRadius: isSelected ? 0.0 : DesignConstants.CornerRadius.regular)
                .fill(isSelected ? Color.colorBorderSubtle2 : Color.colorBackgroundPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.regular)
                        .inset(by: 0.5)
                        .stroke(Color.colorBorderSubtle2,
                                lineWidth: isSelected ? 0.0 : 1.0)
                )
        )
    }
}

#Preview {
    @Previewable @State var isSelected: Bool = false

    ComposerProfileTagView(profile: .mock(),
                           isSelected: isSelected)
    .onTapGesture {
        isSelected.toggle()
    }
}
