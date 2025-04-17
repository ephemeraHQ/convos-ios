//
//  ConversationsView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import SwiftUI

struct ConversationsView: View {
    let authService: AuthServiceProtocol
    var body: some View {
        VStack {
            Spacer()
            
            Button("Sign out") {
                Task {
                   try? await authService.signOut()
                }
            }
            .convosButtonStyle(.text)
            
            Spacer()
        }
    }
}

#Preview {
    ConversationsView(authService: MockAuthService())
}
