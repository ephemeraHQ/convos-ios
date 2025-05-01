import Foundation
import SwiftUI

// swiftlint:disable line_length force_unwrapping

class CTConversationStore: ObservableObject {
    @Published var conversations: [CTConversation] = []
    @Published var currentUser: CTUser
    @Published var showPinLimitAlert: Bool = false
    @Published var conversationAwaitingPin: CTConversation?
    @Published var transitioningConversationId: String?

    private let maxPinnedConversations: Int = 9

    init() {
        // Initialize current user
        self.currentUser = CTUser(
            id: "current-user",
            username: "andrew",
            avatarURL: URL(string: "https://fastly.picsum.photos/id/204/200/200.jpg?hmac=gppQCOIV43fSCLsdUCoPQxrc16lrOEvVu2u5nH-I4Zo")!
        )

        // Load mock data
        self.conversations = Self.generateMockConversations(for: self.currentUser)
    }

    func switchIdentity(to identity: CTUser) {
        currentUser = identity
        conversations = Self.generateMockConversations(for: identity)
    }

    private static func generateMockConversations(for identity: CTUser) -> [CTConversation] {
        switch identity.username {
        case "Convos":
            return generateConvosMockData()
        case "Andrew":
            return generateAndrewMockData()
        case "Incognito":
            return generateIncognitoMockData()
        default:
            return generateConvosMockData()
        }
    }

    private static func generateConvosMockData() -> [CTConversation] {
        let mockUsers = [
            // Requests (5)
            CTUser(id: "user1", username: "koleok", avatarURL: URL(string: "https://fastly.picsum.photos/id/913/200/200.jpg?hmac=MQWqYyJuxoagkUNdhY5lwuKw7QwcqzMEm4otshKpUWQ")!),
            CTUser(id: "user2", username: "darick", avatarURL: URL(string: "https://fastly.picsum.photos/id/677/200/200.jpg?hmac=x54KZ3q80hA0Sc36RV2FUoDZdE3R31oaC988MA1YE2s")!),
            CTUser(id: "user3", username: "saul", avatarURL: URL(string: "https://fastly.picsum.photos/id/686/200/200.jpg?hmac=5DMCllhAJj0gbXXcSZQLQZwnruDJDMVbmFqqwZ6wFug")!),
            CTUser(id: "user4", username: "theirry", avatarURL: URL(string: "https://fastly.picsum.photos/id/409/200/200.jpg?hmac=AY8BYOBixnRqVEMdEhYmw49e-6qu3M3zf_xXjkAuHHc")!),
            CTUser(id: "user5", username: "alex.risch", avatarURL: URL(string: "https://fastly.picsum.photos/id/828/200/200.jpg?hmac=XDYHUvU1Ha9LQrkNk3svII_91vwnQqo8C0yWMqCt6V8")!),

            // Pinned (3)
            CTUser(id: "user6", username: "shanemac", avatarURL: URL(string: "https://fastly.picsum.photos/id/347/200/200.jpg?hmac=HdR0jM_L0Ly35FyTiC7c4NSIkzL0lE_cvesfe-dWAVk")!),
            CTUser(id: "user7", username: "XMTP Gang", avatarURL: URL(string: "https://fastly.picsum.photos/id/921/200/200.jpg?hmac=6pwJUhec4NqIAFxrha-8WXGa8yI1pJXKEYCWMSHroSU")!),
            CTUser(id: "user8", username: "juliet", avatarURL: URL(string: "https://fastly.picsum.photos/id/821/200/200.jpg?hmac=xmadfEZKXLrqLIgmvr2YTIFvhOms4m95Y-KXrpF_VhI")!),

            // Regular chats (17)
            CTUser(id: "user9", username: "converse_team", avatarURL: URL(string: "https://fastly.picsum.photos/id/34/200/200.jpg?hmac=XRWBHNng_p1BDrqV2tGH2Fbk12qD7KRzoufu_JIJW20")!),
            CTUser(id: "user10", username: "fam", avatarURL: URL(string: "https://fastly.picsum.photos/id/63/200/200.jpg?hmac=qWHuiJWhQdWUspXyFKWgfsomzV1IvMNFZQ0hlDl8RZc")!),
            CTUser(id: "user11", username: "crypto_dave", avatarURL: URL(string: "https://fastly.picsum.photos/id/334/200/200.jpg?hmac=Q9rDA3ngheQsAB7HoLSjpzYS0kqelfZIJBGDkW-4wgk")!),
            CTUser(id: "user12", username: "web3_sarah", avatarURL: URL(string: "https://fastly.picsum.photos/id/598/200/200.jpg?hmac=CGTNWD3Wfl8FFUMGok-Kj_SsE7Yc80U-jxup04hpB5k")!),
            CTUser(id: "user13", username: "nft_collector", avatarURL: URL(string: "https://fastly.picsum.photos/id/650/200/200.jpg?hmac=gu3C13pBxCSHokbnumczMYlmWRLt3CFGx1sDaPpfRnk")!),
            CTUser(id: "user14", username: "defi_expert", avatarURL: URL(string: "https://fastly.picsum.photos/id/260/200/200.jpg?hmac=Nu9V4Ixqq3HiFhfkcsL5mNRZAZyEHG2jotmiiMRdxGA")!),
            CTUser(id: "user15", username: "blockchain_dev", avatarURL: URL(string: "https://fastly.picsum.photos/id/288/200/200.jpg?hmac=PrR6Ld35xhRNiCKOIS-dmUjGl-L-3ylEddVJrdwCAHw")!),
            CTUser(id: "user16", username: "eth_trader", avatarURL: URL(string: "https://fastly.picsum.photos/id/174/200/200.jpg?hmac=drl_DcYoPvaGCAF7hzG6zjvSnt77TUxwZFQz_-FDLuI")!),
            CTUser(id: "user17", username: "web3_artist", avatarURL: URL(string: "https://fastly.picsum.photos/id/101/200/200.jpg?hmac=8aiHS9K78DvBexQ7ZROLuLizDR22o8CcjRMUhHbZU6g")!),
            CTUser(id: "user18", username: "dao_member", avatarURL: URL(string: "https://fastly.picsum.photos/id/202/200/200.jpg?hmac=eGzhW5P2k0gzjc76Tk5T9lOfvn30h3YHuw5jGnBUY4Y")!),
            CTUser(id: "user19", username: "defi_analyst", avatarURL: URL(string: "https://fastly.picsum.photos/id/149/200/200.jpg?hmac=ykhZe9T_HysK0voTz01NVBW7C8XlLYYT2EinqAhTA-0")!),
            CTUser(id: "user20", username: "nft_creator", avatarURL: URL(string: "https://fastly.picsum.photos/id/134/200/200.jpg?hmac=a3L-JjVSGeG8w3SdNpzxdh8WSC0xHJXgeD6QryCK7pU")!),
            CTUser(id: "user21", username: "crypto_news", avatarURL: URL(string: "https://fastly.picsum.photos/id/731/200/200.jpg?hmac=f28-4BBT0mjsAystSYFss8hXUcYGvzvo054jqaZG4i0")!),
            CTUser(id: "user22", username: "web3_dev", avatarURL: URL(string: "https://fastly.picsum.photos/id/1067/200/200.jpg?hmac=ngB6HBZNUvsDrt27Y2-MuiSoudFqdwH6bSd8CP8zsy8")!),
            CTUser(id: "user23", username: "defi_architect", avatarURL: URL(string: "https://fastly.picsum.photos/id/284/200/200.jpg?hmac=_el2jO-f8UzHfdcTCAXQOD8XX2N6jqVZHwvC23Xm8p8")!),
            CTUser(id: "user24", username: "nft_curator", avatarURL: URL(string: "https://fastly.picsum.photos/id/242/200/200.jpg?hmac=Z3aa8zbEQkEMFgnVh0Pn96vmCZHhJ17qzCrePYksrcY")!),
            CTUser(id: "user25", username: "crypto_educator", avatarURL: URL(string: "https://fastly.picsum.photos/id/651/200/200.jpg?hmac=p8_kpEZVVgCD0ruS4M5WHOZ2-VETfCi3aXmYAbav3NE")!)
        ]

        let mockMessages = [
            "Hey, do you have time to listen to me whine? About nothing and everything all at once?",
            "All I see is changes",
            "You know California knows how to party 🎉",
            "Just checking in, how's everything going?",
            "Did you see the latest updates?",
            "Can we schedule a quick call?",
            "Important update regarding the project",
            "Have you tried the new feature?",
            "Quick question about the implementation",
            "Thanks for your help earlier!"
        ]

        return mockUsers.enumerated().map { index, user in
            let isRequest = index < 5  // First 5 are requests
            let isPinned = index >= 5 && index < 8  // Next 3 are pinned
            let isUnread = Bool.random()
            let isMuted = Bool.random() && !isRequest
            let amount: Double? = isRequest ? 50 : nil

            let message = CTMessage(
                id: UUID().uuidString,
                content: mockMessages[index % mockMessages.count],
                sender: user,
                timestamp: Date().addingTimeInterval(-Double.random(in: 0...86400))  // Random time in last 24h
            )

            return CTConversation(
                id: UUID().uuidString,
                participants: [user],
                lastMessage: message,
                isPinned: isPinned,
                isUnread: isUnread,
                isRequest: isRequest,
                isMuted: isMuted,
                timestamp: message.timestamp,
                amount: amount
            )
        }
    }

    private static func generateAndrewMockData() -> [CTConversation] {
        let mockUsers = [
            // Request (1)
            CTUser(id: "andrew-user1", username: "jessica", avatarURL: URL(string: "https://fastly.picsum.photos/id/549/200/200.jpg?hmac=8HshVdK-H52hgb-zHj3AefpzafjOnwnqSPzsd0oFoDQ")!),
            // Pinned (1)
            CTUser(id: "andrew-user2", username: "family_group", avatarURL: URL(string: "https://fastly.picsum.photos/id/270/200/200.jpg?hmac=kiH2fdp_jvcCUePVPVJYOa7dhBGLGZOERqNnP0tMFhk")!),
            // Regular chats (3)
            CTUser(id: "andrew-user3", username: "dad", avatarURL: URL(string: "https://fastly.picsum.photos/id/900/200/200.jpg?hmac=ZrAJ9H_K0TLi9qA-7h0aKGGzI3tLtlu1lx6ntCljBfc")!),
            CTUser(id: "andrew-user4", username: "sister", avatarURL: URL(string: "https://fastly.picsum.photos/id/478/200/200.jpg?hmac=YfKBYcZHT991lmrKfB0pYNaztmUvQecXbVrc5V4mj8E")!),
            CTUser(id: "andrew-user5", username: "best_friend", avatarURL: URL(string: "https://fastly.picsum.photos/id/293/200/200.jpg?hmac=6YL5khsW332VGbJLkqIfYLzyXyT1kj358PA64TJtKuw")!)
        ]

        let mockMessages = [
            "Hey, are we still on for dinner tonight?",
            "Can you help me move this weekend?",
            "Did you see the game last night?",
            "Mom wants to know when you're coming home",
            "Let's grab coffee tomorrow"
        ]

        return mockUsers.enumerated().map { index, user in
            let isRequest = index == 0  // First is request
            let isPinned = index == 1   // Second is pinned
            let isUnread = !isRequest && Double.random(in: 0...1) < 0.5
            let isMuted = !isRequest && Bool.random() && !isUnread
            let amount: Double? = isRequest ? 20 : nil

            let message = CTMessage(
                id: UUID().uuidString,
                content: mockMessages[index % mockMessages.count],
                sender: user,
                timestamp: Date().addingTimeInterval(-Double.random(in: 0...86400))
            )

            return CTConversation(
                id: UUID().uuidString,
                participants: [user],
                lastMessage: message,
                isPinned: isPinned,
                isUnread: isUnread,
                isRequest: isRequest,
                isMuted: isMuted,
                timestamp: message.timestamp,
                amount: amount
            )
        }
    }

    private static func generateIncognitoMockData() -> [CTConversation] {
        let mockUsers = [
            // Requests (2)
            CTUser(id: "incognito-user1", username: "anonymous1", avatarURL: URL(string: "https://fastly.picsum.photos/id/200/200/200.jpg?hmac=MQWqYyJuxoagkUNdhY5lwuKw7QwcqzMEm4otshKpUWQ")!),
            CTUser(id: "incognito-user2", username: "anonymous2", avatarURL: URL(string: "https://fastly.picsum.photos/id/201/200/200.jpg?hmac=x54KZ3q80hA0Sc36RV2FUoDZdE3R31oaC988MA1YE2s")!),

            // Regular chats (6)
            CTUser(id: "incognito-user3", username: "private1", avatarURL: URL(string: "https://fastly.picsum.photos/id/202/200/200.jpg?hmac=5DMCllhAJj0gbXXcSZQLQZwnruDJDMVbmFqqwZ6wFug")!),
            CTUser(id: "incognito-user4", username: "private2", avatarURL: URL(string: "https://fastly.picsum.photos/id/203/200/200.jpg?hmac=HdR0jM_L0Ly35FyTiC7c4NSIkzL0lE_cvesfe-dWAVk")!),
            CTUser(id: "incognito-user5", username: "private3", avatarURL: URL(string: "https://fastly.picsum.photos/id/204/200/200.jpg?hmac=6pwJUhec4NqIAFxrha-8WXGa8yI1pJXKEYCWMSHroSU")!),
            CTUser(id: "incognito-user6", username: "private4", avatarURL: URL(string: "https://fastly.picsum.photos/id/205/200/200.jpg?hmac=xmadfEZKXLrqLIgmvr2YTIFvhOms4m95Y-KXrpF_VhI")!),
            CTUser(id: "incognito-user7", username: "private5", avatarURL: URL(string: "https://fastly.picsum.photos/id/206/200/200.jpg?hmac=XRWBHNng_p1BDrqV2tGH2Fbk12qD7KRzoufu_JIJW20")!),
            CTUser(id: "incognito-user8", username: "private6", avatarURL: URL(string: "https://fastly.picsum.photos/id/207/200/200.jpg?hmac=qWHuiJWhQdWUspXyFKWgfsomzV1IvMNFZQ0hlDl8RZc")!)
        ]

        let mockMessages = [
            "The package has been delivered",
            "Meeting at the usual place",
            "Code is ready for review",
            "Documents are in the safe",
            "The transfer is complete",
            "Everything is set up",
            "Waiting for your signal",
            "The target has been acquired",
            "Proceed with the plan",
            "Mission accomplished"
        ]

        return mockUsers.enumerated().map { index, user in
            let isRequest = index < 2  // First 2 are requests
            let isPinned = false  // No pinned chats for incognito
            let isUnread = !isRequest && Double.random(in: 0...1) < 0.1  // 10% chance of unread
            let isMuted = !isRequest && Bool.random() && !isUnread
            let amount: Double? = isRequest ? 50 : nil

            let message = CTMessage(
                id: UUID().uuidString,
                content: mockMessages[index % mockMessages.count],
                sender: user,
                timestamp: Date().addingTimeInterval(-Double.random(in: 0...86400))  // Random time in last 24h
            )

            return CTConversation(
                id: UUID().uuidString,
                participants: [user],
                lastMessage: message,
                isPinned: isPinned,
                isUnread: isUnread,
                isRequest: isRequest,
                isMuted: isMuted,
                timestamp: message.timestamp,
                amount: amount
            )
        }
    }

    // MARK: - Actions

    func togglePin(for conversation: CTConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            if conversations[index].isPinned {
                // Unpinning is always allowed
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    transitioningConversationId = conversation.id
                    conversations[index].isPinned.toggle()
                }

                // Remove the transitioning state after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        self.transitioningConversationId = nil
                    }
                }
            } else {
                // Check if we can pin more conversations
                let pinnedCount = conversations.filter { $0.isPinned }.count
                if pinnedCount >= maxPinnedConversations {
                    conversationAwaitingPin = conversation
                    showPinLimitAlert = true
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        conversations[index].isPinned.toggle()
                    }
                }
            }
        }
    }

    func toggleMute(for conversation: CTConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].isMuted.toggle()
        }
    }

    func toggleRead(for conversation: CTConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].isUnread.toggle()
        }
    }

    func deleteConversation(id: String) {
        conversations.removeAll { $0.id == id }
    }

    // Computed properties for filtered lists
    var pinnedConversations: [CTConversation] {
        conversations.filter { $0.isPinned && $0.id != transitioningConversationId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var unpinnedConversations: [CTConversation] {
        conversations.filter { !$0.isPinned && !$0.isRequest && $0.id != transitioningConversationId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var requests: [CTConversation] {
        conversations.filter { $0.isRequest }.sorted { $0.timestamp > $1.timestamp }
    }
}

// swiftlint:enable line_length force_unwrapping
