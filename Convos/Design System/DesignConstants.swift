import SwiftUI
import UIKit

enum DesignConstants {
    enum ImageSizes {
        static let extraSmallAvatar: CGFloat = 16.0
        static let smallAvatar: CGFloat = 24.0
    }

    enum Spacing {
        static let small: CGFloat = 16.0
        static let medium: CGFloat = 24.0

        static let stepHalf: CGFloat = 2.0
        static let stepX: CGFloat = 4.0
        static let step2x: CGFloat = 8.0
        static let step3x: CGFloat = 12.0
        static let step4x: CGFloat = 16.0
        static let step5x: CGFloat = 20.0
        static let step6x: CGFloat = 24.0
        static let step8x: CGFloat = 32.0
        static let step10x: CGFloat = 40.0
        static let step12x: CGFloat = 48.0
        static let step16x: CGFloat = 64.0
    }

    enum CornerRadius {
        static let large: CGFloat = 40.0
        static let medium: CGFloat = 16.0
        static let regular: CGFloat = 12.0
        static let small: CGFloat = 8.0
    }

    enum Colors {
        static let light: Color = .white
    }

    enum Fonts {
        static let standard: Font = .system(size: 24.0)
        static let medium: Font = .system(size: 16.0)
        static let small: Font = .system(size: 12.0)
        static let buttonText: Font = .system(size: 14.0)
    }
}
