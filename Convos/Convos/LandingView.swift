//
//  LandingView.swift
//  Convos
//
//  Created by Joe on 4/9/25.
//

import SwiftUI

struct LandingView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                VStack(alignment: .center, spacing: 8) {
                    Text("Welcome to Convos")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("Not another\nchat app")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("Super secure · Decentralized · Universal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                VStack(spacing: 32) {
                    VStack {
                        Image(systemName: "person.text.rectangle")
                            .resizable()
                            .frame(width: 50, height: 40)
                            .foregroundColor(.primary)
                            .onTapGesture {
                                print("tapped contact icon")
                            }
                        Text("Create a Contact Card")
                            .font(.body)
                            .foregroundColor(.primary)
                            .onTapGesture {
                                print("tapped create contact card text")
                            }
                    }

                    LegalView()
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 30)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        print("tapped top-right icon")
                    } label: {
                        Image(systemName: "person.badge.key")
                            .font(.title2)
                            .padding()
                            .foregroundStyle(Color(.black))
                    }
                }
            }
        }
    }
}

private struct LegalView: View {
    private let attributedText: AttributedString

    init() {
        var string = AttributedString("When you create a contact card, you agree to the Convos Terms of Service and Privacy Policy.")
        
        // find the range for "Terms of Service" and add the link and foreground color
        if let termsRange = string.range(of: "Terms of Service") {
            string[termsRange].link = URL(string: "https://www.google.com/search?q=terms")
            string[termsRange].foregroundColor = .secondary
            string[termsRange].underlineStyle = .single
        }
        
        // find the range for "Privacy Policy" and add the link and foreground color
        if let privacyRange = string.range(of: "Privacy Policy") {
            string[privacyRange].link = URL(string: "https://www.google.com/search?q=privacy+policy")
            string[privacyRange].foregroundColor = .secondary
            string[privacyRange].underlineStyle = .single
        }
        
        self.attributedText = string
    }

    var body: some View {
        Text(attributedText)
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

    }
}

#Preview {
    LandingView()
}
