import Combine
import ConvosCore
import Observation
import UIKit

@Observable
class ConversationViewModel {
    // MARK: - Private

    private let session: any SessionManagerProtocol

    // These will be loaded asynchronously
    private var myProfileWriter: (any MyProfileWriterProtocol)?
    private var myProfileRepository: (any MyProfileRepositoryProtocol)?
    private var outgoingMessageWriter: (any OutgoingMessageWriterProtocol)?
    private var consentWriter: (any ConversationConsentWriterProtocol)?
    private var localStateWriter: (any ConversationLocalStateWriterProtocol)?
    private var metadataWriter: (any ConversationMetadataWriterProtocol)?

    private let conversationRepository: any ConversationRepositoryProtocol
    private let messagesRepository: any MessagesRepositoryProtocol
    private let inviteRepository: any InviteRepositoryProtocol

    private var cancellables: Set<AnyCancellable> = []
    private var loadProfileImageTask: Task<Void, Never>?
    private var loadConversationImageTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?

    // MARK: - Public

    var loadingError: Error?

    var showsInfoView: Bool = true
    private(set) var conversation: Conversation {
        didSet {
            conversationName = conversation.name ?? ""
            conversationDescription = conversation.description ?? ""
        }
    }
    var messages: [AnyMessage]
    var invite: Invite = .empty
    private(set) var profile: Profile = .empty(inboxId: "") {
        didSet {
            displayName = profile.name ?? ""
        }
    }
    var untitledConversationPlaceholder: String = "Untitled"
    var conversationInfoSubtitle: String {
        conversation.members.count > 1 ? conversation.membersCountString : "Customize"
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
        self.conversationRepository = session.conversationRepository(for: conversation.id)
        self.messagesRepository = session.messagesRepository(for: conversation.id)
        self.inviteRepository = session.inviteRepository(for: conversation.id)
        do {
            self.messages = try messagesRepository.fetchAll()
            self.conversation = try conversationRepository.fetchConversation() ?? conversation
        } catch {
            Logger.error("Error fetching messages or conversation: \(error.localizedDescription)")
            self.messages = []
        }

        observe()

        Logger.info("🔄 created for conversation: \(conversation.id)")

        // Start async initialization
        initializationTask = Task { [weak self] in
            guard let self else { return }
            await self.initializeAsyncDependencies()
        }

        KeyboardListener.shared.add(delegate: self)
    }

    // Alternative initializer for draft conversations with pre-loaded dependencies
    init(
        conversation: Conversation,
        session: any SessionManagerProtocol,
        draftConversationComposer: any DraftConversationComposerProtocol,
        myProfileRepository: any MyProfileRepositoryProtocol
    ) {
        self.conversation = conversation
        self.session = session
        self.conversationName = conversation.name ?? ""
        self.conversationDescription = conversation.description ?? ""
        self.profile = .empty(inboxId: conversation.inboxId)

        // Extract dependencies from draft composer
        self.myProfileWriter = draftConversationComposer.myProfileWriter
        self.myProfileRepository = myProfileRepository
        self.conversationRepository = draftConversationComposer.draftConversationRepository
        self.messagesRepository = draftConversationComposer.draftConversationRepository.messagesRepository
        self.outgoingMessageWriter = draftConversationComposer.draftConversationWriter
        self.consentWriter = draftConversationComposer.conversationConsentWriter
        self.localStateWriter = draftConversationComposer.conversationLocalStateWriter
        self.metadataWriter = draftConversationComposer.conversationMetadataWriter
        self.inviteRepository = draftConversationComposer.draftConversationRepository.inviteRepository
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

        // Update UI state
        self.displayName = profile.name ?? ""
        self.conversationName = conversation.name ?? ""
        self.conversationDescription = conversation.description ?? ""

        KeyboardListener.shared.add(delegate: self)
    }

    @MainActor
    private func initializeAsyncDependencies() async {
        // Get the messaging service
        let messagingService = await session.messagingService(for: conversation.inboxId)

        // Store all the dependencies
        myProfileWriter = messagingService.myProfileWriter()
        myProfileRepository = messagingService.myProfileRepository()
        outgoingMessageWriter = messagingService.messageWriter(for: conversation.id)
        consentWriter = messagingService.conversationConsentWriter()
        localStateWriter = messagingService.conversationLocalStateWriter()
        metadataWriter = messagingService.groupMetadataWriter()

        setupMyProfileRepository()

        // Update UI state
        displayName = profile.name ?? ""
        conversationName = conversation.name ?? ""
        conversationDescription = conversation.description ?? ""

        loadingError = nil
    }

    deinit {
        Logger.info("🗑️ deallocated for conversation: \(conversation.id)")
        cancellables.removeAll()
        initializationTask?.cancel()
        loadProfileImageTask?.cancel()
        loadConversationImageTask?.cancel()
        KeyboardListener.shared.remove(delegate: self)
    }

    // MARK: - Private

    private func setupMyProfileRepository() {
        guard let myProfileRepository else {
            Logger.warning("My profile repository is not available, skipping setup...")
            return
        }

        do {
            self.profile = try myProfileRepository.fetch(inboxId: conversation.inboxId)
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
        inviteRepository.invitePublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] invite in
                self?.invite = invite
            }
            .store(in: &cancellables)
        conversationRepository.conversationPublisher
            .dropFirst()
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

        if conversationName != (conversation.name ?? "") {
            Task { [weak self] in
                guard let self, let metadataWriter = self.metadataWriter else { return }
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

            Task { [weak self] in
                guard let self, let metadataWriter = self.metadataWriter else { return }
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

        if conversationDescription != (conversation.description ?? "") {
            Task { [weak self] in
                guard let self, let metadataWriter = self.metadataWriter else { return }
                do {
                    try await metadataWriter.updateGroupDescription(
                        groupId: conversation.id,
                        description: conversationDescription
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
            guard let self, let outgoingMessageWriter = self.outgoingMessageWriter else { return }
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

        if (profile.name ?? "") != displayName {
            Task { [weak self] in
                guard let self, let myProfileWriter = self.myProfileWriter else { return }
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

            Task { [weak self] in
                guard let self, let myProfileWriter = self.myProfileWriter else { return }
                do {
                    try await myProfileWriter.update(avatar: profileImage)
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
            guard let self, let metadataWriter = self.metadataWriter else { return }
            do {
                try await metadataWriter.removeGroupMembers(groupId: conversation.id, memberInboxIds: [member.profile.inboxId])
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
                focus = nil
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

        let inboxId = conversation.inboxId
        let conversationId = conversation.id
        Task { [weak self] in
            guard let self,
                  let metadataWriter = self.metadataWriter,
                  let outgoingMessageWriter = self.outgoingMessageWriter else {
                return
            }

            focus = nil
            presentingConversationSettings = false

            do {
                try await outgoingMessageWriter.sendExplode()

                let memberIdsToRemove = conversation.members
                    .filter { !$0.isCurrentUser } // @jarodl fix when we have self removal
                    .map { $0.profile.inboxId }
                try await metadataWriter.removeGroupMembers(
                    groupId: conversation.id,
                    memberInboxIds: memberIdsToRemove
                )

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .leftConversationNotification,
                        object: nil,
                        userInfo: ["inboxId": inboxId, "conversationId": conversationId]
                    )
                }
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
