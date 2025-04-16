//
//  ButtonStyles.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import SwiftUI

enum ConvosButtonStyleType {
    case outline(fullWidth: Bool)
}

extension Button {
    func convosButtonStyle(_ styleType: ConvosButtonStyleType) -> some View {
        switch styleType {
        case .outline(let fullWidth):
            return self.buttonStyle(OutlineButtonStyle(fullWidth: fullWidth))
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    let fullWidth: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .applyIf(fullWidth) { view in
                view.frame(maxWidth: .infinity)
            }
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, DesignConstants.Spacing.step3x)
            .padding(.horizontal, DesignConstants.Spacing.step6x)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium)
                    .stroke(.colorBorderSubtle2, lineWidth: 1.0)
            )
            .foregroundColor(isEnabled ? .colorTextPrimary : .colorTextTertiary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

#Preview {
    Button("Outline Button Style Disabled") {}
        .convosButtonStyle(.outline(fullWidth: true))
        .disabled(true)
    
    Button("Outline Button Style Enabled") {}
        .convosButtonStyle(.outline(fullWidth: true))
}
