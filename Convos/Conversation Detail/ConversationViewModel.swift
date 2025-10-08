import Combine
import ConvosCore
import Observation
import UIKit

@Observable
class ConversationViewModel {
    // MARK: - Private

    private let session: any SessionManagerProtocol
    private let myProfileWriter: any MyProfileWriterProtocol
    private let myProfileRepository: any MyProfileRepositoryProtocol
    private let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    private let consentWriter: any ConversationConsentWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let metadataWriter: any ConversationMetadataWriterProtocol
    private let conversationRepository: any ConversationRepositoryProtocol
    private let messagesRepository: any MessagesRepositoryProtocol

    private var cancellables: Set<AnyCancellable> = []
    private var loadProfileImageTask: Task<Void, Never>?
    private var loadConversationImageTask: Task<Void, Never>?

    // MARK: - Public

    var showsInfoView: Bool = true
    private(set) var conversation: Conversation {
        didSet {
            // Only update if the actual name changed (not just last message)
            if oldValue.name != conversation.name {
                conversationName = conversation.name ?? ""
            }
            // Only update if the actual description changed
            if oldValue.description != conversation.description {
                conversationDescription = conversation.description ?? ""
            }
        }
    }
    var messages: [AnyMessage]
    var invite: Invite {
        conversation.invite ?? .empty
    }
    private(set) var profile: Profile = .empty(inboxId: "")
    var untitledConversationPlaceholder: String = "Untitled"
    var conversationInfoSubtitle: String {
        !conversation.hasJoined || conversation.members.count > 1 ? conversation.membersCountString : "Customize"
    }
    var conversationNamePlaceholder: String = "Name"
    var conversationDescriptionPlaceholder: String = "Description"
    var joinEnabled: Bool = true
    var notificationsEnabled: Bool = true
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
    var showsExplodeNowButton: Bool {
        conversation.members.count > 1 && conversation.creator.isCurrentUser
    }
    var sendButtonEnabled: Bool = false
    var profileImage: UIImage?
    /// we manage focus in the view model along with @FocusState in the view
    /// since programatically changing @FocusState doesn't always propagate to child views
    var focus: MessagesViewInputFocus?
    var presentingConversationSettings: Bool = false
    var presentingProfileSettings: Bool = false
    var presentingProfileForMember: ConversationMember?

    var useDisplayNameForNewConvos: Bool = false

    // MARK: - Init

    init(
        conversation: Conversation,
        session: any SessionManagerProtocol
    ) {
        self.conversation = conversation
        self.session = session
        self.conversationName = conversation.name ?? ""
        self.conversationDescription = conversation.description ?? ""
        self.profile = .empty(inboxId: conversation.inboxId)
        self.conversationRepository = session.conversationRepository(
            for: conversation.id,
            inboxId: conversation.inboxId
        )
        self.messagesRepository = session.messagesRepository(for: conversation.id)
        do {
            self.messages = try messagesRepository.fetchAll()
            self.conversation = try conversationRepository.fetchConversation() ?? conversation
        } catch {
            Logger.error("Error fetching messages or conversation: \(error.localizedDescription)")
            self.messages = []
        }

        let messagingService = session.messagingService(for: conversation.inboxId)
        myProfileWriter = messagingService.myProfileWriter()
        myProfileRepository = conversationRepository.myProfileRepository
        outgoingMessageWriter = messagingService.messageWriter(for: conversation.id)
        consentWriter = messagingService.conversationConsentWriter()
        localStateWriter = messagingService.conversationLocalStateWriter()
        metadataWriter = messagingService.conversationMetadataWriter()

        setupMyProfileRepository()

        // Initialize UI state only if not already set
        if displayName.isEmpty {
            displayName = profile.name ?? ""
        }
        if conversationName.isEmpty {
            conversationName = conversation.name ?? ""
        }
        if conversationDescription.isEmpty {
            conversationDescription = conversation.description ?? ""
        }

        Logger.info("Created for conversation: \(conversation.id)")

        observe()

        KeyboardListener.shared.add(delegate: self)
    }

    // Alternative initializer for draft conversations with pre-loaded dependencies
    init(
        conversation: Conversation,
        session: any SessionManagerProtocol,
        conversationStateManager: any ConversationStateManagerProtocol,
        myProfileRepository: any MyProfileRepositoryProtocol
    ) {
        self.conversation = conversation
        self.session = session
        self.conversationName = conversation.name ?? ""
        self.conversationDescription = conversation.description ?? ""
        self.profile = .empty(inboxId: conversation.inboxId)

        // Extract dependencies from conversation state manager
        self.myProfileWriter = conversationStateManager.myProfileWriter
        self.myProfileRepository = myProfileRepository
        self.conversationRepository = conversationStateManager.draftConversationRepository
        self.messagesRepository = conversationStateManager.draftConversationRepository.messagesRepository
        self.outgoingMessageWriter = conversationStateManager
        self.consentWriter = conversationStateManager.conversationConsentWriter
        self.localStateWriter = conversationStateManager.conversationLocalStateWriter
        self.metadataWriter = conversationStateManager.conversationMetadataWriter
        do {
            self.messages = try messagesRepository.fetchAll()
            self.conversation = try conversationRepository.fetchConversation() ?? conversation
        } catch {
            Logger.error("Error fetching messages or conversation: \(error.localizedDescription)")
            self.messages = []
        }

        Logger.info("🔄 created for draft conversation: \(conversation.id)")

        observe()
        setupMyProfileRepository()

        // Initialize UI state only if not already set
        if displayName.isEmpty {
            self.displayName = profile.name ?? ""
        }
        if conversationName.isEmpty {
            self.conversationName = conversation.name ?? ""
        }
        if conversationDescription.isEmpty {
            self.conversationDescription = conversation.description ?? ""
        }

        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        Logger.info("🗑️ deallocated for conversation: \(conversation.id)")
        cancellables.removeAll()
        loadProfileImageTask?.cancel()
        loadConversationImageTask?.cancel()
        KeyboardListener.shared.remove(delegate: self)
    }

    // MARK: - Private

    private func setupMyProfileRepository() {
        do {
            self.profile = try myProfileRepository.fetch()
        } catch {
            Logger.error("Failed fetching my profile: \(error.localizedDescription)")
        }

        myProfileRepository.myProfilePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.profile = profile
            }
            .store(in: &cancellables)
    }

    private func observe() {
        messagesRepository.messagesPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.messages = messages
            }
            .store(in: &cancellables)
        conversationRepository.conversationPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] conversation in
                self?.conversation = conversation
            }
            .store(in: &cancellables)
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

        let trimmedConversationName = conversationName.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationName = trimmedConversationName

        if trimmedConversationName != (conversation.name ?? "") {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await metadataWriter.updateName(
                        trimmedConversationName,
                        for: conversation.id
                    )
                } catch {
                    Logger.error("Failed updating group name: \(error)")
                }
            }
        }

        if let conversationImage = conversationImage {
            ImageCache.shared.setImage(conversationImage, for: conversation)

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await metadataWriter.updateImage(
                        conversationImage,
                        for: conversation
                    )
                } catch {
                    Logger.error("Failed updating group image: \(error)")
                }
            }
        }

        let trimmedConversationDescription = conversationDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationDescription = trimmedConversationDescription

        if trimmedConversationDescription != (conversation.description ?? "") {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await metadataWriter.updateDescription(
                        trimmedConversationDescription,
                        for: conversation.id
                    )
                } catch {
                    Logger.error("Failed updating group description: \(error)")
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

    func onProfileSettingsDismissed() {
        onDisplayNameEndedEditing(nextFocus: nil)
        presentingProfileSettings = false
    }

    func onSendMessage() {
        let prevMessageText = messageText
        messageText = ""
        Task { [weak self] in
            guard let self else { return }
            do {
                try await outgoingMessageWriter.send(text: prevMessageText)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
        }
    }

    func onTapMessage(_ message: AnyMessage) {
        presentingProfileForMember = message.base.sender
    }

    func onDisplayNameEndedEditing() {
        onDisplayNameEndedEditing(nextFocus: .message)
    }

    private func onDisplayNameEndedEditing(nextFocus: MessagesViewInputFocus?) {
        focus = nextFocus

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmedDisplayName

        if (profile.name ?? "") != trimmedDisplayName {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await myProfileWriter.update(displayName: trimmedDisplayName, conversationId: conversation.id)
                } catch {
                    Logger.error("Error updating profile display name: \(error.localizedDescription)")
                }
            }
        }

        // @jarodl check if the image was actually changed
        if let profileImage {
            ImageCache.shared.setImage(profileImage, for: profile)

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await myProfileWriter.update(avatar: profileImage, conversationId: conversation.id)
                } catch {
                    Logger.error("Error updating profile image: \(error.localizedDescription)")
                }
            }
        }
    }

    func onProfileSettings() {
        presentingProfileSettings = true
    }

    func remove(member: ConversationMember) {
        guard canRemoveMembers else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await metadataWriter.removeMembers([member.profile.inboxId], from: conversation.id)
            } catch {
                Logger.error("Error removing member: \(error.localizedDescription)")
            }
        }
    }

    func leaveConvo() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await session.deleteInbox(inboxId: conversation.inboxId)
                presentingConversationSettings = false
                NotificationCenter.default.post(
                    name: .leftConversationNotification,
                    object: nil,
                    userInfo: ["inboxId": conversation.inboxId, "conversationId": conversation.id]
                )
            } catch {
                Logger.error("Error leaving convo: \(error.localizedDescription)")
            }
        }
    }

    func explodeConvo() {
        guard canRemoveMembers else { return }

        NotificationCenter.default.post(
            name: .leftConversationNotification,
            object: nil,
            userInfo: ["inboxId": conversation.inboxId, "conversationId": conversation.id]
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let memberIdsToRemove = conversation.members
                    .filter { !$0.isCurrentUser } // @jarodl fix when we have self removal
                    .map { $0.profile.inboxId }
                try await metadataWriter.removeMembers(
                    memberIdsToRemove,
                    from: conversation.id
                )
                try await session.deleteInbox(inboxId: conversation.inboxId)
                presentingConversationSettings = false
            } catch {
                Logger.error("Error exploding convo: \(error.localizedDescription)")
            }
        }
    }
}

extension ConversationViewModel: KeyboardListenerDelegate {
    func keyboardDidHide(info: KeyboardInfo) {
        focus = nil
    }
}

extension ConversationViewModel {
    static var mock: ConversationViewModel {
        return .init(
            conversation: .mock(),
            session: MockInboxesService()
        )
    }
}
