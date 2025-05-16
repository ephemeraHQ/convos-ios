import Foundation
import SwiftUI

struct ChatListView: View {
    @State var userState: UserState
    @State var conversationsStore: ConversationsStore
    @State private var selectedConversation: ConversationItem?

    @State private var showDropdownMenu: Bool = false

    init(messagingService: any ConvosSDK.MessagingServiceProtocol,
         userRepository: any UserRepositoryProtocol) {
        _userState = State(wrappedValue: .init(userRepository: userRepository))
        _conversationsStore = State(wrappedValue: ConversationsStore(messagingService: messagingService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ChatListNavigationBar(
                        userState: userState,
                        onIdentityTap: {
                            showDropdownMenu = true
                        },
                        onQRTap: {
                            print("QR tapped")
                        },
                        onWalletTap: {
                            print("Wallet tapped")
                        },
                        onComposeTap: {
                            print("Compose tapped")
                        }
                    )

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Regular chats
                            ForEach(conversationsStore.unpinnedConversations) { conversation in
                                ChatListItem(
                                    conversationItem: conversation,
                                    onTap: {
                                        print("tapping on regular chat")
                                        selectedConversation = conversation
                                    },
                                    onPin: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                            conversationsStore.togglePin(for: conversation)
                                        }
                                    },
                                    onToggleRead: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                            conversationStore.toggleRead(for: conversation)
                                        }
                                    },
                                    onToggleMute: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                            conversationStore.toggleMute(for: conversation)
                                        }
                                    },
                                    onDelete: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                            conversationStore.deleteConversation(id: conversation.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .navigationBarHidden(true)
                .navigationDestination(item: $selectedConversation) { _ in
                    MessagesView(messagesStore: MockMessagesStore())
                        .ignoresSafeArea()
                        .toolbarVisibility(.hidden, for: .navigationBar)
                        .toolbarVisibility(.hidden, for: .navigationBar)
                }

                // Dropdown menu overlay
                if showDropdownMenu {
                    DropdownMenu(
                        sections: dropdownMenuSections,
                        onDismiss: { showDropdownMenu = false }
                    )
                    .zIndex(10)
                }
            }
        }
    }

    // Build the dropdown menu data
    private var dropdownMenuSections: [DropdownMenuSection] {
        [
            DropdownMenuSection(items: [
                DropdownMenuItem(
                    title: "App Settings",
                    subtitle: nil,
                    icon: Image("gear"),
                    isSelected: false,
                    isIdentity: false,
                    action: {
                        print("App Settings tapped")
                        showDropdownMenu = false
                    }
                )
            ])
        ]
    }
}

#Preview {
//    ChatListView(conversationStore: CTConversationStore(), identityStore: CTIdentityStore())
}
