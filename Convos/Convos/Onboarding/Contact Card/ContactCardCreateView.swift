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
    @State private var isEditingContactCard: Bool = true
    @State private var hasAppeared: Bool = false
    @State private var isVisible: Bool = true
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: DesignConstants.Spacing.medium) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .convosButtonStyle(.text)
                
                Spacer()
            }
            .padding(.top, DesignConstants.Spacing.step3x)
            .opacity(isEditingContactCard ? 1.0 : 0.0)
            
            Spacer(minLength: 0.0)
            
            VStack(spacing: DesignConstants.Spacing.medium) {
                if !isNameFocused && hasAppeared && isEditingContactCard {
                    VStack(spacing: DesignConstants.Spacing.small) {
                        Text("Complete your contact card")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .padding(.top, DesignConstants.Spacing.step6x)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Choose how you show up")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                DraggableSpringyView {
                    ContactCardView(name: $name,
                                    imageState: $imageState,
                                    nameIsValid: $nameIsValid,
                                    nameError: $nameError,
                                    isEditing: $isEditingContactCard,
                                    isNameFocused: $isNameFocused,
                                    importAction: {
                        importCardAction()
                    })
                }
                .zIndex(1)
                .overlay(alignment: .bottom) {
                    if let nameError = nameError {
                        Text(nameError)
                            .font(.subheadline)
                            .foregroundStyle(.colorCaution)
                            .multilineTextAlignment(.center)
                            .offset(y: DesignConstants.Spacing.step10x)
                    }
                }
                .rotation3DEffect(
                    .degrees(hasAppeared ? 0.0 : 15.0),
                    axis: (x: 1.0, y: 0.0, z: 0.0)
                )
                .offset(y: hasAppeared ? 0.0 : 40.0)
                .animation(.spring(duration: 0.6, bounce: 0.5).delay(0.1), value: hasAppeared)
                
                if !isNameFocused && hasAppeared && nameError == nil {
                    Text(isEditingContactCard ? "You can update this anytime." : "Looks good!")
                        .font(.subheadline)
                        .foregroundStyle(Color.colorTextSecondary)
                        .padding(.bottom, DesignConstants.Spacing.step6x)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(0)
                }
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            
            Spacer(minLength: 0.0)
            
            Button("That's me") {
                // temporary animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    isEditingContactCard = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        submitAction()
                    }
                }
            }
            .convosButtonStyle(.outline(fullWidth: true))
            .opacity(isEditingContactCard ? 1.0 : 0.0)
            .disabled(!nameIsValid)
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.bottom, DesignConstants.Spacing.step3x)
            .zIndex(0)
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .padding(.horizontal, DesignConstants.Spacing.step3x)
        .background(.colorBackgroundPrimary)
        .animation(.easeInOut(duration: 0.3), value: isNameFocused)
        .animation(.easeInOut(duration: 0.2), value: hasAppeared)
        .animation(.easeInOut(duration: 0.2), value: isEditingContactCard)
        .onAppear {
            hasAppeared = true
        }
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
