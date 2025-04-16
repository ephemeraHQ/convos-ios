//
//  ContactCardCreateView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/15/25.
//

import SwiftUI

struct ContactCardCreateView: View {
    @State var name: String = ""
    @State var imageState: ContactCardImage.State = .empty
    @State var isValidName: Bool = true
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
            
            ContactCardEditView(name: $name, imageState: $imageState, isValidName: $isValidName, isNameFocused: $isNameFocused, importAction: {
                // import contact card
            })
            
            Text("You can update this anytime.")
                .font(.subheadline)
                .foregroundStyle(Color.colorTextSecondary)
                .offset(y: isNameFocused ? 40 : 0)
                .opacity(isNameFocused ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isNameFocused)
                .padding(.bottom, DesignConstants.Spacing.step6x)
            
            Spacer()
            
            Button("That's me") {
                
            }
            .convosButtonStyle(.outline(fullWidth: true))
            
        }
        .padding(.horizontal, 28.0)
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    ContactCardCreateView()
}
