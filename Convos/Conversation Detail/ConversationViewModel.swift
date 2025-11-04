import Combine
import ConvosCore
import Observation
import UIKit

@MainActor
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

    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Public

    var showsInfoView: Bool = true
    private(set) var conversation: Conversation {
        didSet {
            presentingConversationForked = conversation.isForked
            if !isEditingConversationName {
                editingConversationName = conversation.name ?? ""
            }
            if !isEditingDescription {
                editingDescription = conversation.description ?? ""
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
        (
            !conversation.hasJoined || conversation.members.count > 1
        ) && !conversation.isDraft ? conversation.membersCountString : "Customize"
    }
    var conversationNamePlaceholder: String = "Name"
    var conversationDescriptionPlaceholder: String = "Description"
    var joinEnabled: Bool = true
    var notificationsEnabled: Bool = true
    // Editing state flags
    var isEditingDisplayName: Bool = false
    var isEditingConversationName: Bool = false
    var isEditingDescription: Bool = false

    // Editing values
    var editingDisplayName: String = ""
    var editingConversationName: String = ""
    var editingDescription: String = ""

    // Computed properties for display
    var displayName: String {
        isEditingDisplayName ? editingDisplayName : profile.name ?? ""
    }

    var conversationName: String {
        isEditingConversationName ? editingConversationName : conversation.name ?? ""
    }

    var conversationDescription: String {
        isEditingDescription ? editingDescription : conversation.description ?? ""
    }
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
    var focus: MessagesViewInputFocus? {
        didSet {
            switch focus {
            case .displayName:
                isEditingDisplayName = true
                isEditingConversationName = false
            case .conversationName:
                isEditingConversationName = true
                isEditingDisplayName = false
            default:
                isEditingConversationName = false
                isEditingDisplayName = false
            }
        }
    }
    var presentingConversationSettings: Bool = false
    var presentingProfileSettings: Bool = false
    var presentingProfileForMember: ConversationMember?
    var presentingConversationForked: Bool = false

    var useDisplayNameForNewConvos: Bool = false
    var shouldAskToAllowNotifications: Bool = false

    // MARK: - Init

    init(
        conversation: Conversation,
        session: any SessionManagerProtocol
    ) {
        self.conversation = conversation
        self.session = session
        self.profile = .empty(inboxId: conversation.inboxId)
        self.conversationRepository = session.conversationRepository(
            for: conversation.id,
            inboxId: conversation.inboxId,
            clientId: conversation.clientId
        )
        self.messagesRepository = session.messagesRepository(for: conversation.id)

        let messagingService = session.messagingService(
            for: conversation.clientId,
            inboxId: conversation.inboxId
        )
        myProfileWriter = messagingService.myProfileWriter()
        myProfileRepository = conversationRepository.myProfileRepository
        outgoingMessageWriter = messagingService.messageWriter(for: conversation.id)
        consentWriter = messagingService.conversationConsentWriter()
        localStateWriter = messagingService.conversationLocalStateWriter()
        metadataWriter = messagingService.conversationMetadataWriter()

        do {
            self.messages = try messagesRepository.fetchAll()
            self.conversation = try conversationRepository.fetchConversation() ?? conversation
            self.profile = try myProfileRepository.fetch()
        } catch {
            Logger.error("Error fetching messages or conversation: \(error.localizedDescription)")
            self.messages = []
        }

        setupMyProfileRepository()

        editingDisplayName = profile.name ?? ""
        editingConversationName = conversation.name ?? ""
        editingDescription = conversation.description ?? ""

        presentingConversationForked = conversation.isForked

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
            self.profile = try myProfileRepository.fetch()
        } catch {
            Logger.error("Error fetching messages or conversation: \(error.localizedDescription)")
            self.messages = []
        }

        Logger.info("🔄 created for draft conversation: \(conversation.id)")

        observe()
        setupMyProfileRepository()

        self.editingDisplayName = profile.name ?? ""
        self.editingConversationName = conversation.name ?? ""
        self.editingDescription = conversation.description ?? ""

        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        KeyboardListener.shared.remove(delegate: self)
    }

    // MARK: - Private

    private func setupMyProfileRepository() {
        myProfileRepository.myProfilePublisher
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

    func checkNotificationPermissions() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await updateNotificationPermissions()
        }
    }

    @MainActor
    func updateNotificationPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.shouldAskToAllowNotifications = settings.authorizationStatus == .notDetermined
    }

    func requestPushNotificationsPermission() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await PushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()
            await updateNotificationPermissions()
        }
    }

    func onConversationInfoTap() {
        focus = .conversationName
    }

    func onConversationNameEndedEditing() {
        onConversationNameEndedEditing(nextFocus: .message)
    }

    func onConversationNameEndedEditing(nextFocus: MessagesViewInputFocus?) {
        focus = nextFocus

        let trimmedConversationName = editingConversationName.trimmingCharacters(in: .whitespacesAndNewlines)
        editingConversationName = trimmedConversationName

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

        let trimmedConversationDescription = editingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        editingDescription = trimmedConversationDescription

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

    func onConversationSettingsCancelled() {
        isEditingConversationName = false
        isEditingDescription = false
        editingConversationName = conversation.name ?? ""
        editingDescription = conversation.description ?? ""
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
    }

    func onTapAvatar(_ message: AnyMessage) {
        presentingProfileForMember = message.base.sender
    }

    func onDisplayNameEndedEditing() {
        onDisplayNameEndedEditing(nextFocus: .message)
    }

    private func onDisplayNameEndedEditing(nextFocus: MessagesViewInputFocus?) {
        focus = nextFocus

        let trimmedDisplayName = editingDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        editingDisplayName = trimmedDisplayName

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
                try await session.deleteInbox(clientId: conversation.clientId)
                await MainActor.run {
                    self.presentingConversationSettings = false
                    self.conversation.postLeftConversationNotification()
                }
            } catch {
                Logger.error("Error leaving convo: \(error.localizedDescription)")
            }
        }
    }

    func explodeConvo() {
        guard canRemoveMembers else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let memberIdsToRemove = conversation.members
                    .filter { !$0.isCurrentUser } // @jarodl fix when we have self removal
                    .map { $0.profile.inboxId }
                // set the expiration to now
                try await metadataWriter.updateExpiresAt(Date(), for: conversation.id)
                // remove everyone anyway
                try await metadataWriter.removeMembers(
                    memberIdsToRemove,
                    from: conversation.id
                )
                try await session.deleteInbox(clientId: conversation.clientId)
                conversation.postLeftConversationNotification()
                presentingConversationSettings = false
            } catch {
                Logger.error("Error exploding convo: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func exportDebugLogs() async throws -> URL {
        // Get the XMTP client for this conversation
        let messagingService = session.messagingService(
            for: conversation.clientId,
            inboxId: conversation.inboxId
        )

        // Wait for inbox to be ready and get the client
        let inboxResult = try await messagingService.inboxStateManager.waitForInboxReadyResult()
        let client = inboxResult.client

        guard let xmtpConversation = try await client.conversation(with: conversation.id) else {
            throw NSError(
                domain: "ConversationViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Conversation not found"]
            )
        }

        return try await xmtpConversation.exportDebugLogs()
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
