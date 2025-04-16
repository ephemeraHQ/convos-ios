//
//  LandingView.swift
//  Convos
//
//  Created by Joe on 4/9/25.
//

import SwiftUI

#Preview {
    LandingView()
}

struct LandingView: View {
    var body: some View {
        VStack(spacing: DesignConstants.Spacing.step4x) {
            
            HStack(spacing: DesignConstants.Spacing.step2x) {
                Circle()
                    .foregroundStyle(.colorOrange)
                    .frame(width: DesignConstants.ImageSizes.smallAvatar, height: DesignConstants.ImageSizes.smallAvatar)
                Text("Convos")
                    .font(.subheadline)
                    .foregroundStyle(.colorTextPrimary)
                
                Spacer()
                
                Button("Sign in") {
                    
                }
                .convosButtonStyle(.text)
            }
            .padding(.leading, DesignConstants.Spacing.step3x)
            .padding(.top, 10.0)
            
            Spacer()
            
            VStack(spacing: DesignConstants.Spacing.step4x) {
                Text("Not another chat app")
                    .font(.system(size: 56.0, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("Super secure · Decentralized · Universal")
                    .font(.subheadline)
                    .foregroundStyle(.colorTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignConstants.Spacing.stepX)
            
            Spacer()
            
            VStack(spacing: DesignConstants.Spacing.step4x) {
                Button("Create your Contact Card") {
                    
                }
                .convosButtonStyle(.rounded(fullWidth: true))
                
                LegalView()
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.top, DesignConstants.Spacing.step2x)
            .padding(.bottom, DesignConstants.Spacing.step6x)
        }
        .padding(.horizontal, DesignConstants.Spacing.step3x)
    }
}

private struct LegalView: View {
    var body: some View {
        Group {
            Text("When you create a contact card, you agree to the Convos ")
            + Text("[Terms](https://xmtp.org/terms)")
                .underline()
            + Text(" and ")
            + Text("[Privacy Policy](https://xmtp.org/privacy)")
                .underline()
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .tint(.secondary)
        .foregroundColor(.secondary)
    }
}
