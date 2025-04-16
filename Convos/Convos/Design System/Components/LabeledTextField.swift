//
//  LabeledTextField.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/15/25.
//

import SwiftUI

struct LabeledTextField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    @State private var borderColor: Color = .colorBorderSubtle
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        LabeledContent {
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(.colorTextTertiary))
                .foregroundStyle(Color.colorTextPrimary)
                .font(DesignConstants.Fonts.medium)
                .focused($isFocused)
        } label: {
            Text(label)
                .foregroundStyle(.colorTextPrimary)
                .font(DesignConstants.Fonts.small)
        }
        .labeledContentStyle(.vertical)
        .padding(.vertical, DesignConstants.Spacing.step2x)
        .padding(.horizontal, DesignConstants.Spacing.step3x)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.small)
                .inset(by: 0.5)
                .stroke(borderColor, lineWidth: 1.0)
        )
    }
}

extension LabeledTextField {
    func textFieldBorder(_ color: Color) -> some View {
        var copy = self
        copy._borderColor = State(initialValue: color)
        return copy
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    LabeledTextField(label: "Name", prompt: "Nice to meet you", text: .constant(""),
                     isFocused: $isFocused)
}
