import Foundation
import GRDB
import SwiftUI

// swiftlint:disable force_unwrapping line_length

class CTIdentityStore: ObservableObject {
    @Published var currentIdentity: CTUser
    @Published var availableIdentities: [CTUser]
    @Published var isIdentityPickerPresented: Bool = false

    static let mockIdentities: [CTUser] = [
        CTUser(
            id: "identity1",
            username: "Convos",
            avatarURL: URL(string: "https://fastly.picsum.photos/id/913/200/200.jpg?hmac=MQWqYyJuxoagkUNdhY5lwuKw7QwcqzMEm4otshKpUWQ")!
        ),
        CTUser(
            id: "identity2",
            username: "Andrew",
            avatarURL: URL(string: "https://fastly.picsum.photos/id/677/200/200.jpg?hmac=x54KZ3q80hA0Sc36RV2FUoDZdE3R31oaC988MA1YE2s")!
        ),
        CTUser(
            id: "identity3",
            username: "Incognito",
            avatarURL: URL(string: "https://fastly.picsum.photos/id/686/200/200.jpg?hmac=5DMCllhAJj0gbXXcSZQLQZwnruDJDMVbmFqqwZ6wFug")!
        )
    ]

    init() {
        // Mock identities
        self.availableIdentities = CTIdentityStore.mockIdentities
        self.currentIdentity = CTIdentityStore.mockIdentities[0]
    }

    func switchIdentity(to identity: CTUser) {
        currentIdentity = identity
        isIdentityPickerPresented = false
    }
}

// swiftlint:enable force_unwrapping line_length
