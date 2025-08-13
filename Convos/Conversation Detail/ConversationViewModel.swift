import Combine
import Observation
import UIKit

@Observable
class ConversationViewModel {
    // MARK: - Private

    private let session: any SessionManagerProtocol
    private let myProfileWriter: any MyProfileWriterProtocol
    private let myProfileRepository: any MyProfileRepositoryProtocol
    private let conversationRepository: any ConversationRepositoryProtocol
    private let messagesRepository: any MessagesRepositoryProtocol
    private let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    private let consentWriter: any ConversationConsentWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let metadataWriter: any ConversationMetadataWriterProtocol
    private let inviteRepository: any InviteRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = []
    private var loadProfileImageTask: Task<Void, Never>?
    private var loadConversationImageTask: Task<Void, Never>?

    // MARK: - Public

    var conversation: Conversation {
        didSet {
            conversationName = conversation.name ?? ""
        }
    }
    var messages: [AnyMessage] = []
    var invite: Invite = .empty
    var profile: Profile {
        didSet {
            Logger.info("Updated profile: \(profile)")
            displayName = profile.name ?? ""
        }
    }
    var untitledConversationPlaceholder: String = "Untitled"
    var conversationNamePlaceholder: String = "Name"
    var conversationDescriptionPlaceholder: String = "Description"
    var joinEnabled: Bool = true
    var displayName: String = ""
    var conversationName: String = ""
    var conversationDescription: String = ""
    var conversationImage: UIImage?
    var messageText: String = "" {
        didSet {
            sendButtonEnabled = !messageText.isEmpty
        }
    }
    var canRemoveMembers: Bool {
        conversation.creator.isCurrentUser
    }
    var sendButtonEnabled: Bool = false
    var profileImage: UIImage?
    /// we manage focus in the view model along with @FocusState in the view
    /// since programatically changing @FocusState doesn't always propagate to child views
    var focus: MessagesViewInputFocus?
    var presentingConversationSettings: Bool = false

    // MARK: - Init

    init(
        conversation: Conversation,
        session: any SessionManagerProtocol,
        myProfileWriter: any MyProfileWriterProtocol,
        myProfileRepository: any MyProfileRepositoryProtocol,
        conversationRepository: any ConversationRepositoryProtocol,
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        consentWriter: any ConversationConsentWriterProtocol,
        localStateWriter: any ConversationLocalStateWriterProtocol,
        metadataWriter: any ConversationMetadataWriterProtocol,
        inviteRepository: any InviteRepositoryProtocol
    ) {
        self.conversation = conversation
        self.session = session
        self.myProfileWriter = myProfileWriter
        self.myProfileRepository = myProfileRepository
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.consentWriter = consentWriter
        self.localStateWriter = localStateWriter
        self.metadataWriter = metadataWriter
        self.inviteRepository = inviteRepository
        self.profile = .empty(inboxId: conversation.inboxId)

        fetchLatest()
        observe()

        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        KeyboardListener.shared.remove(delegate: self)
    }

    // MARK: - Private

    private func fetchLatest() {
        do {
            self.profile = try myProfileRepository.fetch(inboxId: conversation.inboxId)
            self.conversation = try conversationRepository.fetchConversation() ?? conversation
            self.messages = try messagesRepository.fetchAll()
        } catch {
            Logger.error("Error fetching latest: \(error.localizedDescription)")
        }
    }

    private func observe() {
        myProfileRepository.myProfilePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.profile, on: self)
            .store(in: &cancellables)
        messagesRepository.messagesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
        inviteRepository.invitePublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .assign(to: \.invite, on: self)
            .store(in: &cancellables)
        conversationRepository.conversationPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .assign(to: \.conversation, on: self)
            .store(in: &cancellables)
    }

    private func markConversationAsRead() {
        Task { [localStateWriter] in
            do {
                try await localStateWriter.setUnread(false, for: conversation.id)
            } catch {
                Logger.error("Error marking conversation as read: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Public

    func onConversationInfoTap() {
        focus = .conversationName
    }

    func onConversationNameEndedEditing() {
        onConversationNameEndedEditing(nextFocus: .message)
    }

    func onConversationNameEndedEditing(nextFocus: MessagesViewInputFocus?) {
        focus = nextFocus

        if conversationName != conversation.name {
            Task { [metadataWriter] in
                do {
                    try await metadataWriter.updateGroupName(
                        groupId: conversation.id,
                        name: conversationName
                    )
                } catch {
                    Logger.error("Failed updating group name: \(error)")
                }
            }
        }

        if let conversationImage = conversationImage {
            ImageCache.shared.setImage(conversationImage, for: conversation)

            Task { [metadataWriter] in
                do {
                    try await metadataWriter.updateGroupImage(
                        conversation: conversation,
                        image: conversationImage
                    )
                } catch {
                    Logger.error("Failed updating group image: \(error)")
                }
            }
        }
    }

    func onConversationSettings() {
        presentingConversationSettings = true
        focus = nil
    }

    func onConversationSettingsDismissed() {
        onConversationNameEndedEditing(nextFocus: nil)
        presentingConversationSettings = false
    }

    func onProfilePhotoTap() {
        focus = .displayName
    }

    func onSendMessage() {
        let prevMessageText = messageText
        messageText = ""
        Task { [outgoingMessageWriter] in
            do {
                try await outgoingMessageWriter.send(text: prevMessageText)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
        }
    }

    func onDisplayNameEndedEditing() {
        onDisplayNameEndedEditing(nextFocus: .message)
    }

    private func onDisplayNameEndedEditing(nextFocus: MessagesViewInputFocus?) {
        focus = nextFocus

        if profile.name != displayName {
            Task { [myProfileWriter] in
                do {
                    try await myProfileWriter.update(displayName: displayName)
                } catch {
                    Logger.error("Error updating profile display name: \(error.localizedDescription)")
                }
            }
        }

        // @jarodl check if the image was actually changed
        if let profileImage {
            ImageCache.shared.setImage(profileImage, for: profile)

            Task { [myProfileWriter] in
                do {
                    try await myProfileWriter.update(avatar: profileImage)
                } catch {
                    Logger.error("Error updating profile image: \(error.localizedDescription)")
                }
            }
        }
    }

    func onProfileSettings() {
    }

    func onAppear() {
        markConversationAsRead()
    }

    func onDisappear() {
        markConversationAsRead()
    }

    func remove(member: ConversationMember) {
        guard canRemoveMembers else { return }
        Task {
            do {
                try await metadataWriter.removeGroupMembers(groupId: conversation.id, memberInboxIds: [member.profile.inboxId])
            } catch {
                Logger.error("Error removing member: \(error.localizedDescription)")
            }
        }
    }

    func leaveConvo() {
        do {
            try session.deleteAccount(inboxId: conversation.inboxId)
        } catch {
            Logger.error("Error leaving convo: \(error.localizedDescription)")
        }
    }

    func explodeConvo() {
        guard canRemoveMembers else { return }
        Task {
            do {
                let memberIdsToRemove = conversation.members
                    .filter { !$0.isCurrentUser } // @jarodl fix when we have self removal
                    .map { $0.profile.inboxId }
                try await metadataWriter.removeGroupMembers(
                    groupId: conversation.id,
                    memberInboxIds: memberIdsToRemove
                )
                try session.deleteAccount(inboxId: conversation.inboxId)
            } catch {
                Logger.error("Error exploding convo: \(error.localizedDescription)")
            }
        }
    }
}

extension ConversationViewModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(conversation)
    }

    static func == (lhs: ConversationViewModel, rhs: ConversationViewModel) -> Bool {
        return lhs.conversation == rhs.conversation
    }
}

extension ConversationViewModel: KeyboardListenerDelegate {
    func keyboardDidHide(info: KeyboardInfo) {
        focus = nil
    }
}

extension ConversationViewModel {
    static var mock: ConversationViewModel {
        let messaging = MockMessagingService()
        return .init(
            conversation: .mock(),
            session: MockInboxesService(),
            myProfileWriter: MockMyProfileWriter(),
            myProfileRepository: messaging,
            conversationRepository: MockConversationRepository(),
            messagesRepository: messaging,
            outgoingMessageWriter: MockOutgoingMessageWriter(),
            consentWriter: MockConversationConsentWriter(),
            localStateWriter: MockConversationLocalStateWriter(),
            metadataWriter: MockGroupMetadataWriter(),
            inviteRepository: MockInviteRepository()
        )
    }
}
