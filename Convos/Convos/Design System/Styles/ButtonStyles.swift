//
//  ButtonStyles.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import SwiftUI

enum ConvosButtonStyleType {
    case outline(fullWidth: Bool), text, rounded(fullWidth: Bool)
}

extension Button {
    func convosButtonStyle(_ styleType: ConvosButtonStyleType) -> some View {
        switch styleType {
        case .outline(let fullWidth):
            return AnyView(self.buttonStyle(OutlineButtonStyle(fullWidth: fullWidth)))
        case .text:
            return AnyView(self.buttonStyle(TextButtonStyle()))
        case .rounded(let fullWidth):
            return AnyView(self.buttonStyle(RoundedButtonStyle(fullWidth: fullWidth)))
        }
    }
}

struct RoundedButtonStyle: ButtonStyle {
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
            .padding(.horizontal, DesignConstants.Spacing.step4x)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .background(.colorFillPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium))
            .foregroundColor(isEnabled ? .colorTextPrimaryInverted : .colorTextTertiary)
    }
}

struct TextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.colorTextSecondary)
            .padding(.vertical, DesignConstants.Spacing.step2x)
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .opacity(isEnabled ? configuration.isPressed ? 0.6 : 1.0 : 0.3)
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
            .padding(.horizontal, DesignConstants.Spacing.step4x)
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
    VStack(spacing: DesignConstants.Spacing.step4x) {
        Button("Outline Button Style - Disabled") {}
            .convosButtonStyle(.outline(fullWidth: true))
            .disabled(true)
        
        Button("Outline Button Style - Enabled") {}
            .convosButtonStyle(.outline(fullWidth: true))
        
        Button("Text Button Style - Disabled") {}
            .convosButtonStyle(.text)
            .disabled(true)
        
        Button("Text Button Style") {}
            .convosButtonStyle(.text)
        
        Button("Rounded Button Style") {}
            .convosButtonStyle(.rounded(fullWidth: true))
        
        Button("Rounded Button Style - Disabled") {}
            .convosButtonStyle(.rounded(fullWidth: true))
            .disabled(true)
    }
    .padding(.horizontal, DesignConstants.Spacing.step6x)
}
