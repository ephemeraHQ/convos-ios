import Combine
import Observation
import UIKit

@Observable
class ConversationViewModel {
    // MARK: - Private

    private let myProfileWriter: any MyProfileWriterProtocol
    private let myProfileRepository: any MyProfileRepositoryProtocol
    private let conversationRepository: any ConversationRepositoryProtocol
    private let messagesRepository: any MessagesRepositoryProtocol
    private let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    private let consentWriter: any ConversationConsentWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let metadataWriter: any GroupMetadataWriterProtocol
    private let inviteRepository: any InviteRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = []
    private var loadProfileImageTask: Task<Void, Never>?
    private var loadConversationImageTask: Task<Void, Never>?

    // MARK: - Public

    var conversation: Conversation {
        didSet {
            conversationName = conversation.name ?? ""
            loadConversationImage(from: conversation.imageURL)
        }
    }
    var messages: [AnyMessage] = []
    var invite: Invite = .empty
    var profile: Profile = .empty() {
        didSet {
            displayName = profile.name ?? ""
            loadProfileImage(from: profile.avatarURL)
        }
    }
    var untitledConversationPlaceholder: String = "Untitled"
    var conversationNamePlaceholder: String = "Name"
    var displayName: String = ""
    var conversationName: String = ""
    var conversationImage: UIImage?
    var messageText: String = "" {
        didSet {
            sendButtonEnabled = !messageText.isEmpty
        }
    }
    var sendButtonEnabled: Bool = false
    var profileImage: UIImage?
    var focus: MessagesViewInputFocus?

    // MARK: - Init

    init(
        conversation: Conversation,
        myProfileWriter: any MyProfileWriterProtocol,
        myProfileRepository: any MyProfileRepositoryProtocol,
        conversationRepository: any ConversationRepositoryProtocol,
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        consentWriter: any ConversationConsentWriterProtocol,
        localStateWriter: any ConversationLocalStateWriterProtocol,
        metadataWriter: any GroupMetadataWriterProtocol,
        inviteRepository: any InviteRepositoryProtocol
    ) {
        self.conversation = conversation
        self.myProfileWriter = myProfileWriter
        self.myProfileRepository = myProfileRepository
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.consentWriter = consentWriter
        self.localStateWriter = localStateWriter
        self.metadataWriter = metadataWriter
        self.inviteRepository = inviteRepository

        fetchLatest()
        observe()
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

    private func loadConversationImage(from imageURL: URL?) {
        loadConversationImageTask?.cancel()
        loadConversationImageTask = loadImage(from: imageURL, for: conversation, assignTo: { [weak self] image in
            self?.conversationImage = image
        })
    }

    private func loadProfileImage(from imageURL: URL?) {
        loadProfileImageTask?.cancel()
        loadProfileImageTask = loadImage(from: imageURL, for: profile) { [weak self] image in
            self?.profileImage = image
        }
    }

    // MARK: - Public

    func onConversationInfoTap() {
        focus = .conversationName
    }

    func onConversationNameEndedEditing() {
        focus = .message

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
        focus = .message

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
}

extension ConversationViewModel {
    static var mock: ConversationViewModel {
        let messaging = MockMessagingService()
        return .init(
            conversation: .mock(),
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

extension ConversationViewModel {
    private func loadImage<T: ImageCacheable>(
        from imageURL: URL?,
        for cacheableObject: T,
        assignTo setter: @escaping (UIImage?) -> Void
    ) -> Task<Void, Never>? {
        guard let imageURL else {
            return nil
        }

        if let existingImage = ImageCache.shared.image(for: imageURL) {
            setter(existingImage)
            return nil
        }

        return Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let image = UIImage(data: data) {
                    // Cache the image for future use
                    ImageCache.shared.setImage(image, for: imageURL.absoluteString)

                    // Also cache by object if available for instant cross-view updates
                    ImageCache.shared.setImage(image, for: cacheableObject)

                    await MainActor.run {
                        setter(image)
                    }
                }
            } catch {
                await MainActor.run {
                    setter(nil)
                }
            }
        }
    }
}
