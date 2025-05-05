import Foundation
import SwiftUI

struct ChatListView: View {
    @ObservedObject var conversationStore: CTConversationStore
    @ObservedObject var identityStore: CTIdentityStore
    @State private var showDropdownMenu: Bool = false
    @State private var selectedConversation: CTConversation?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ChatListNavigationBar(
                        currentIdentity: identityStore.currentIdentity,
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
                            // Pinned chats grid
                            if !conversationStore.pinnedConversations.isEmpty {
                                PinnedChatsGrid(
                                    conversations: conversationStore.pinnedConversations,
                                    onTapChat: { conversation in
                                        print("tapping on pinned chat")
                                        selectedConversation = conversation
                                    },
                                    onUnpin: { conversation in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.togglePin(for: conversation)
                                        }
                                    },
                                    onToggleRead: { conversation in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.toggleRead(for: conversation)
                                        }
                                    },
                                    onToggleMute: { conversation in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.toggleMute(for: conversation)
                                        }
                                    },
                                    onDelete: { conversation in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.deleteConversation(id: conversation.id)
                                        }
                                    }
                                )
                                .background(Color(.systemBackground))
                            }

                            // Requests section
                            if !conversationStore.requests.isEmpty {
                                RequestsHeader(
                                    requestCount: conversationStore.requests.count,
                                    amount: conversationStore.requests.first?.amount,
                                    onTap: {
                                        print("Navigate to requests list")
                                    }
                                )
                            }

                            // Regular chats
                            ForEach(conversationStore.unpinnedConversations) { conversation in
                                ChatListItem(
                                    conversation: conversation,
                                    onTap: {
                                        print("tapping on regular chat")
                                        selectedConversation = conversation
                                    },
                                    onPin: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.togglePin(for: conversation)
                                        }
                                    },
                                    onToggleRead: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.toggleRead(for: conversation)
                                        }
                                    },
                                    onToggleMute: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.toggleMute(for: conversation)
                                        }
                                    },
                                    onDelete: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            conversationStore.deleteConversation(id: conversation.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .navigationBarHidden(true)
                .navigationDestination(item: $selectedConversation) { conversation in
                    MessagesView(messagingService: MockMessagingService())
                        .ignoresSafeArea()
                        .navigationTitle(conversation.otherParticipant?.username ?? "Chat")
                        .navigationBarTitleDisplayMode(.inline)
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
            .alert("Pinned Conversations", isPresented: $conversationStore.showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can pin up to 9 conversations. To pin this conversation, unpin another one first.")
            }
            .sheet(isPresented: $identityStore.isIdentityPickerPresented) {
                NavigationView {
                    List(identityStore.availableIdentities) { identity in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                identityStore.switchIdentity(to: identity)
                            }
                        } label: {
                            HStack {
                                AsyncImage(url: identity.avatarURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(.systemGray5)
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())

                                Text(identity.username)
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)

                                Spacer()

                                if identity.id == identityStore.currentIdentity.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .navigationTitle("Switch Identity")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                identityStore.isIdentityPickerPresented = false
                            }
                        }
                    }
                }
            }
        }
    }

    // Build the dropdown menu data
    private var dropdownMenuSections: [DropdownMenuSection] {
        [
            DropdownMenuSection(items: identityStore.availableIdentities.map { identity in
                DropdownMenuItem(
                    title: identity.username,
                    subtitle: identity.username == "Convos" ? "All chats" : nil,
                    icon: nil,
                    isSelected: identity.id == identityStore.currentIdentity.id,
                    isIdentity: true,
                    action: {
                        identityStore.switchIdentity(to: identity)
                        conversationStore.switchIdentity(to: identity)
                        showDropdownMenu = false
                    }
                )
            }),
            DropdownMenuSection(items: [
                DropdownMenuItem(
                    title: "New Contact Card",
                    subtitle: nil,
                    icon: Image("contactCard"),
                    isSelected: false,
                    isIdentity: false,
                    action: {
                        print("New Contact Card tapped")
                        showDropdownMenu = false
                    }
                )
            ]),
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
    ChatListView(conversationStore: CTConversationStore(), identityStore: CTIdentityStore())
}
