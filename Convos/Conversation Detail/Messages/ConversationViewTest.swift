//import SwiftUI
//
//struct ConversationViewTest: View {
//    let conversationId: String = "1"
//    static var messaging: any MessagingServiceProtocol = MockMessagingService()
//    let messagesRepository: any MessagesRepositoryProtocol = Self.messaging.messagesRepository(for: "1")
//    let inviteRepository: any InviteRepositoryProtocol = Self.messaging.inviteRepository(for: "1")
//
//    @State private var inputViewHeight: CGFloat = 0.0 {
//        didSet {
//            Logger.info("Input view height: \(inputViewHeight)")
//        }
//    }
//
//    @State private var messageText: String = ""
//    @State private var profileImage: UIImage?
//    @State private var viewModel: MessagesInputViewModel = .init(myProfileWriter: MockMyProfileWriter(), outgoingMessageWriter: MockOutgoingMessageWriter())
//
//    var body: some View {
//        GeometryReader { reader in
//            NavigationStack {
//                ZStack {
//                    Group {
//                        MessagesViewRepresentable(
//                            conversationId: "1",
//                            messages: [],
//                            invite: .empty,
//                            inputViewHeight: inputViewHeight
//                        )
//                        .ignoresSafeArea()
//                    }
//                    .toolbarTitleDisplayMode(.inline)
//                    .toolbar {
//                        ToolbarItem(placement: .topBarLeading) {
//                            Button(role: .cancel) {
//                                //
//                            }
//                        }
//                        ToolbarItem(placement: .topBarTrailing) {
//                            InviteShareLink(invite: .mock())
//                        }
//                    }
//
//                    VStack {
//                    }
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .safeAreaBar(edge: .bottom) {
//                        MessagesBottomBar(
//                            messageText: $messageText,
//                            profileImage: $profileImage
//                        )
//                        .background(HeightReader())
//                        .onPreferenceChange(HeightPreferenceKey.self) { height in
//                            inputViewHeight = height
//                        }
//                    }
//
//                    VStack {
//                        Button {
//                            //
//                        } label: {
//                            Text("Testing")
//                                .padding()
//                        }
//                        .buttonStyle(GlassButtonStyle())
//                        .zIndex(1000)
//                        .padding(.top, reader.safeAreaInsets.top)
//
//                        Spacer()
//                    }
//                    .ignoresSafeArea(edges: .top)
//                }
//            }
//        }
////        .onChange(of: viewModel.showingProfileNameEditor) { oldValue, newValue in
////            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
////                progress = newValue ? 1.0 : 0.0
////            }
////        }
//    }
//}
//
//#Preview {
//    ConversationViewTest()
//}
