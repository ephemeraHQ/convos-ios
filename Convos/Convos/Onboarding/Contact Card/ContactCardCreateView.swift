//
//  ContactCardCreateView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/15/25.
//

import SwiftUI

struct ContactCardCreateView: View {
    @Binding var name: String
    @Binding var imageState: ContactCardImage.State
    @Binding var nameIsValid: Bool
    @Binding var nameError: String?
    let importCardAction: () -> Void
    let submitAction: () -> Void
    @FocusState var isNameFocused: Bool
    
    var body: some View {
        VStack(spacing: DesignConstants.Spacing.medium) {
            Spacer()
            
            VStack(spacing: DesignConstants.Spacing.small) {
                Text("Complete your contact card")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignConstants.Spacing.step6x)
                
                Text("Choose how you show up")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .offset(y: isNameFocused ? -40 : 0)
            .opacity(isNameFocused ? 0.0 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isNameFocused)
            
                ContactCardEditView(name: $name, imageState: $imageState, nameIsValid: $nameIsValid, nameError: $nameError, isNameFocused: $isNameFocused, importAction: {
                    importCardAction()
                })
                .overlay(alignment: .bottom) {
                    if let nameError = nameError {
                        Text(nameError)
                            .font(.subheadline)
                            .foregroundStyle(.colorCaution)
                            .multilineTextAlignment(.center)
                            .offset(y: DesignConstants.Spacing.step10x)
                    }
                }
            
            Text("You can update this anytime.")
                .font(.subheadline)
                .foregroundStyle(Color.colorTextSecondary)
                .padding(.bottom, DesignConstants.Spacing.step6x)
                .offset(y: isNameFocused ? 40 : 0)
                .opacity(isNameFocused ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isNameFocused)
            
            Spacer()
            
            Button("That's me") {
                submitAction()
            }
            .convosButtonStyle(.outline(fullWidth: true))
            .disabled(!nameIsValid)
            
        }
        .padding(.horizontal, 28.0)
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    @Previewable @State var name: String = ""
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var nameIsValid: Bool = false
    @Previewable @State var nameError: String? = nil
    ContactCardCreateView(name: $name,
                          imageState: $imageState,
                          nameIsValid: $nameIsValid,
                          nameError: $nameError, importCardAction: {
        // import
    }) {
        // submit
    }
}
