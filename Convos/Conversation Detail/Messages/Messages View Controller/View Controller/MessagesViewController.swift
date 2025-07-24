import Combine
import DifferenceKit
import Foundation
import SwiftUI
import UIKit

final class MessagesViewController: UIViewController {
    private enum ReactionTypes {
        case delayedUpdate
    }

    private enum InterfaceActions {
        case changingKeyboardFrame
        case changingContentInsets
        case changingFrameSize
        case sendingMessage
        case scrollingToTop
        case scrollingToBottom
        case updatingCollectionInIsolation
        case showingReactionsMenu
    }

    private enum ControllerActions {
        case loadingInitialMessages
        case loadingPreviousMessages
        case updatingCollection
    }

    // MARK: - Properties

    private var currentInterfaceActions: SetActor<Set<InterfaceActions>, ReactionTypes> = SetActor()
    private var currentControllerActions: SetActor<Set<ControllerActions>, ReactionTypes> = SetActor()

    let collectionView: UICollectionView
    private var messagesLayout: MessagesCollectionLayout = MessagesCollectionLayout()

    private let dataSource: MessagesCollectionDataSource

    private var animator: ManualAnimator?

    private var isUserInitiatedScrolling: Bool {
        collectionView.isDragging || collectionView.isDecelerating
    }

    let messagesRepository: any MessagesRepositoryProtocol
    private let inviteRepository: any InviteRepositoryProtocol
    private var messagesRepositoryCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var conversationHasMembers: Bool = false

    private var reactionMenuCoordinator: MessageReactionMenuCoordinator?

    // MARK: - Initialization

    init(
        messagesRepository: any MessagesRepositoryProtocol,
        inviteRepository: any InviteRepositoryProtocol
    ) {
        self.dataSource = MessagesCollectionViewDataSource()
        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: messagesLayout
        )
        self.messagesRepository = messagesRepository
        self.inviteRepository = inviteRepository
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        messagesRepositoryCancellable?.cancel()
        KeyboardListener.shared.remove(delegate: self)
    }

    @available(*, unavailable, message: "Use init(messageController:) instead")
    override convenience init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError()
    }

    @available(*, unavailable, message: "Use init(messageController:) instead")
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: -

    func observe(
        messagesRepository: any MessagesRepositoryProtocol,
        inviteRepository: any InviteRepositoryProtocol
    ) {
        messagesRepositoryCancellable?.cancel()
        messagesRepositoryCancellable = nil

        let messagesPublisher = messagesRepository
            .conversationMessagesPublisher
            .withPrevious()

        let invitePublisher = inviteRepository
            .invitePublisher
            .map { $0 as Invite? }
            .prepend(nil)

        self.messagesRepositoryCancellable = Publishers.CombineLatest(
            messagesPublisher,
            invitePublisher
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] messagesData, invite in
            guard let self else { return }
            let (previous, current) = messagesData
            let animated = previous.conversationId == current.conversationId
            processUpdates(
                with: current.messages,
                invite: invite,
                animated: animated,
                requiresIsolatedProcess: true) {
                    if previous.conversationId != current.conversationId {
                        UIView.performWithoutAnimation {
                            self.scrollToBottom()
                        }
                    }
                }
        }
    }

    private func reloadMessagesFromRepository() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                let messages = try messagesRepository.fetchAll()
                processUpdates(
                    with: messages,
                    invite: nil,
                    animated: true,
                    requiresIsolatedProcess: false
                )
            } catch {
                Logger.error("Error fetching messages: \(error)")
            }
        }
    }

    // MARK: - Lifecycle Methods

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupUI()
        reactionMenuCoordinator = MessageReactionMenuCoordinator(delegate: self)

        reloadMessagesFromRepository()
        observe(messagesRepository: messagesRepository, inviteRepository: inviteRepository)

        NotificationCenter.default.addObserver(
            forName: .messagesInputViewHeightDidChange,
            object: nil,
            queue: .main
        ) { notification in
            if let height = notification.object as? CGFloat {
                Logger.info("Messages input height changed to: \(height)")
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        handleViewTransition(to: size, with: coordinator)
        super.viewWillTransition(to: size, with: coordinator)
    }

    // MARK: - Private Setup Methods

    private func setupUI() {
        view.backgroundColor = .clear
        KeyboardListener.shared.add(delegate: self)
    }

    private func setupCollectionView() {
        collectionView.frame = view.bounds
        configureMessagesLayout()
        setupCollectionViewInstance()
        configureCollectionViewConstraints()
        configureCollectionViewBehavior()
    }

    private func configureMessagesLayout() {
        messagesLayout.settings.interItemSpacing = 8
        messagesLayout.settings.interSectionSpacing = 8
        messagesLayout.settings.additionalInsets = UIEdgeInsets(top: 8, left: 5, bottom: 8.0, right: 5)
        messagesLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        messagesLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = true
    }

    private func setupCollectionViewInstance() {
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
    }

    private func configureCollectionViewConstraints() {
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func configureCollectionViewBehavior() {
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        messagesLayout.delegate = dataSource
        collectionView.keyboardDismissMode = .interactive

        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.automaticallyAdjustsScrollIndicatorInsets = true
        collectionView.selfSizingInvalidation = .enabled
        messagesLayout.supportSelfSizingInvalidation = true

        dataSource.prepare(with: collectionView)
    }

    private func handleViewTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        guard isViewLoaded else { return }

        currentInterfaceActions.options.insert(.changingFrameSize)
        let positionSnapshot = messagesLayout.getContentOffsetSnapshot(from: .bottom)
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.setNeedsLayout()

        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.performBatchUpdates(nil)
        }, completion: { _ in
            if let positionSnapshot,
               !self.isUserInitiatedScrolling {
                self.messagesLayout.restoreContentOffset(with: positionSnapshot)
            }
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.currentInterfaceActions.options.remove(.changingFrameSize)
        })
    }

    // MARK: - Scrolling Methods

    private func loadPreviousMessages() {
        //        currentControllerActions.options.insert(.loadingPreviousMessages)
        //        Task {
        //            let sections = await messagesStore.loadPreviousMessages()
        //            let animated = !isUserInitiatedScrolling
        //            processUpdates(with: sections, animated: animated, requiresIsolatedProcess: true) {
        //                self.currentControllerActions.options.remove(.loadingPreviousMessages)
        //            }
        //        }
    }

    func scrollToBottom(completion: (() -> Void)? = nil) {
        let contentOffsetAtBottom = CGPoint(
            x: collectionView.contentOffset.x,
            y: (messagesLayout.collectionViewContentSize.height -
                collectionView.frame.height +
                collectionView.adjustedContentInset.bottom)
        )

        guard contentOffsetAtBottom.y > collectionView.contentOffset.y else {
            completion?()
            return
        }

        performScrollToBottom(from: contentOffsetAtBottom,
                              initialOffset: collectionView.contentOffset.y,
                              completion: completion)
    }

    private func performScrollToBottom(from contentOffsetAtBottom: CGPoint,
                                       initialOffset: CGFloat,
                                       completion: (() -> Void)?) {
        let delta: CGFloat = contentOffsetAtBottom.y - initialOffset

        if abs(delta) > messagesLayout.visibleBounds.height {
            performLongScrollToBottom(initialOffset: initialOffset, delta: delta, completion: completion)
        } else {
            performShortScrollToBottom(to: contentOffsetAtBottom, completion: completion)
        }
    }

    private func performLongScrollToBottom(initialOffset: CGFloat, delta: CGFloat, completion: (() -> Void)?) {
        animator = ManualAnimator()
        animator?.animate(duration: TimeInterval(0.25), curve: .easeInOut) { [weak self] percentage in
            guard let self else { return }

            collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x,
                                                   y: initialOffset + (delta * percentage))

            if percentage == 1.0 {
                animator = nil
                let positionSnapshot = MessagesLayoutPositionSnapshot(indexPath: IndexPath(item: 0, section: 0),
                                                                      kind: .footer,
                                                                      edge: .bottom)
                messagesLayout.restoreContentOffset(with: positionSnapshot)
                currentInterfaceActions.options.remove(.scrollingToBottom)
                completion?()
            }
        }
    }

    private func performShortScrollToBottom(to contentOffsetAtBottom: CGPoint, completion: (() -> Void)?) {
        currentInterfaceActions.options.insert(.scrollingToBottom)
        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            self?.collectionView.setContentOffset(contentOffsetAtBottom, animated: true)
        }, completion: { [weak self] _ in
            self?.currentInterfaceActions.options.remove(.scrollingToBottom)
            completion?()
        })
    }
}

// MARK: - MessagesControllerDelegate

extension MessagesViewController {
    private func processUpdates(with messages: [AnyMessage],
                                invite: Invite?,
                                animated: Bool = true,
                                requiresIsolatedProcess: Bool,
                                completion: (() -> Void)? = nil) {
        var cells: [MessagesCollectionCell] = messages.enumerated().flatMap { index, message in
            var cells: [MessagesCollectionCell] = []

            let senderTitleCell = MessagesCollectionCell.messageGroup(
                .init(
                    id: message.base.sender.id,
                    title: message.base.sender.profile.displayName,
                    source: message.base.source
                )
            )

            if index > 0 {
                let previousMessage = messages[index - 1]
                let timeDifference = message.base.date.timeIntervalSince(previousMessage.base.date)
                if timeDifference > 3600 { // 1 hour in seconds
                    cells.append(MessagesCollectionCell.date(.init(date: message.base.date)))
                }
                if previousMessage.base.sender.id != message.base.sender.id, message.base.source.isIncoming {
                    cells.append(senderTitleCell)
                }
            } else {
                cells.append(MessagesCollectionCell.date(.init(date: message.base.date)))
                if message.base.source.isIncoming {
                    cells.append(senderTitleCell)
                }
            }

            let bubbleType: MessagesCollectionCell.BubbleType
            if index < messages.count - 1 {
                let nextMessage = messages[index + 1]
                bubbleType = message.base.sender.id == nextMessage.base.sender.id ? .normal : .tailed
            } else {
                bubbleType = .tailed
            }
            cells.append(MessagesCollectionCell.message(message, bubbleType: bubbleType))
            return cells
        }

        if let invite {
            cells.insert(.invite(invite, verticalPadding: messages.isEmpty), at: 0)
        }

        let sections: [MessagesCollectionSection] = [
            .init(id: 0, title: "", cells: cells)
        ]
        guard isViewLoaded else {
            dataSource.sections = sections
            return
        }

        guard currentInterfaceActions.options.isEmpty else {
            scheduleDelayedUpdate(with: messages,
                                  invite: invite,
                                  animated: animated,
                                  requiresIsolatedProcess: requiresIsolatedProcess,
                                  completion: completion)
            return
        }

        performUpdate(with: sections,
                      animated: animated,
                      requiresIsolatedProcess: requiresIsolatedProcess,
                      completion: completion)
    }

    private func scheduleDelayedUpdate(with messages: [AnyMessage],
                                       invite: Invite?,
                                       animated: Bool,
                                       requiresIsolatedProcess: Bool,
                                       completion: (() -> Void)?) {
        let reaction = SetActor<Set<InterfaceActions>, ReactionTypes>.Reaction(
            type: .delayedUpdate,
            action: .onEmpty,
            executionType: .once,
            actionBlock: { [weak self] in
                guard let self else { return }
                processUpdates(with: messages,
                               invite: invite,
                               animated: animated,
                               requiresIsolatedProcess: requiresIsolatedProcess,
                               completion: completion)
            })
        currentInterfaceActions.add(reaction: reaction)
    }

    private func performUpdate(with sections: [MessagesCollectionSection],
                               animated: Bool,
                               requiresIsolatedProcess: Bool,
                               completion: (() -> Void)?) {
        let process = {
            let changeSet = StagedChangeset(source: self.dataSource.sections, target: sections).flattenIfPossible()

            guard !changeSet.isEmpty else {
                completion?()
                return
            }

            if requiresIsolatedProcess {
                self.messagesLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = true
                self.currentInterfaceActions.options.insert(.updatingCollectionInIsolation)
            }

            self.currentControllerActions.options.insert(.updatingCollection)
            self.collectionView.reload(
                using: changeSet,
                interrupt: { changeSet in
                    !changeSet.sectionInserted.isEmpty
                },
                onInterruptedReload: {
                    let positionSnapshot = MessagesLayoutPositionSnapshot(
                        indexPath: IndexPath(item: 0, section: sections.count - 1),
                        kind: .footer,
                        edge: .bottom
                    )
                    self.collectionView.reloadData()
                    self.messagesLayout.restoreContentOffset(with: positionSnapshot)
                },
                completion: { _ in
                    DispatchQueue.main.async {
                        self.messagesLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
                        if requiresIsolatedProcess {
                            self.currentInterfaceActions.options.remove(.updatingCollectionInIsolation)
                        }
                        completion?()
                        self.currentControllerActions.options.remove(.updatingCollection)
                    }
                },
                setData: { data in
                    self.dataSource.sections = data
                }
            )
        }

        if animated {
            process()
        } else {
            UIView.performWithoutAnimation {
                process()
            }
        }
    }
}

// MARK: - UIScrollViewDelegate & UICollectionViewDelegate

extension MessagesViewController: UIScrollViewDelegate, UICollectionViewDelegate {
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard scrollView.contentSize.height > 0,
              !currentInterfaceActions.options.contains(.scrollingToTop),
              !currentInterfaceActions.options.contains(.scrollingToBottom) else {
            return false
        }

        currentInterfaceActions.options.insert(.scrollingToTop)
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        guard !currentControllerActions.options.contains(.loadingInitialMessages),
              !currentControllerActions.options.contains(.loadingPreviousMessages) else {
            return
        }
        currentInterfaceActions.options.remove(.scrollingToTop)
        loadPreviousMessages()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleScrollViewDidScroll(scrollView)
    }

    private func handleScrollViewDidScroll(_ scrollView: UIScrollView) {
        if currentControllerActions.options.contains(.updatingCollection), collectionView.isDragging {
            interruptCurrentUpdateAnimation()
        }

        guard !currentControllerActions.options.contains(.loadingInitialMessages),
              !currentControllerActions.options.contains(.loadingPreviousMessages),
              !currentInterfaceActions.options.contains(.scrollingToTop),
              !currentInterfaceActions.options.contains(.scrollingToBottom) else {
            return
        }

        if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top {
            loadPreviousMessages()
        }
    }

    private func interruptCurrentUpdateAnimation() {
        UIView.performWithoutAnimation {
            self.collectionView.performBatchUpdates({}, completion: { _ in
                let context = MessagesLayoutInvalidationContext()
                context.invalidateLayoutMetrics = false
                self.collectionView.collectionViewLayout.invalidateLayout(with: context)
            })
        }
    }
}

// MARK: - KeyboardListenerDelegate

extension MessagesViewController: KeyboardListenerDelegate {
    func keyboardWillChangeFrame(info: KeyboardInfo) {
        handleKeyboardFrameChange(info: info)
    }

    func keyboardDidChangeFrame(info: KeyboardInfo) {
        guard currentInterfaceActions.options.contains(.changingKeyboardFrame) else { return }
        currentInterfaceActions.options.remove(.changingKeyboardFrame)
    }

    private func handleKeyboardFrameChange(info: KeyboardInfo) {
        guard shouldHandleKeyboardFrameChange(info: info) else { return }

        currentInterfaceActions.options.insert(.changingKeyboardFrame)
        let newBottomInset = calculateNewBottomInset(for: info)
        guard newBottomInset > 0,
              collectionView.contentInset.bottom != newBottomInset else { return }

        updateCollectionViewInsets(to: newBottomInset, with: info)
    }

    private func shouldHandleKeyboardFrameChange(info: KeyboardInfo) -> Bool {
        guard !currentInterfaceActions.options.contains(.changingFrameSize),
              !currentInterfaceActions.options.contains(.showingReactionsMenu),
              collectionView.contentInsetAdjustmentBehavior != .never,
              let keyboardFrame = collectionView.window?.convert(info.frameEnd, to: view),
              keyboardFrame.minY > 0,
              collectionView.convert(collectionView.bounds, to: collectionView.window).maxY > info.frameEnd.minY else {
            return false
        }
        return true
    }

    private func calculateNewBottomInset(for info: KeyboardInfo) -> CGFloat {
        let keyboardFrame = collectionView.window?.convert(info.frameEnd, to: view)
        return (collectionView.frame.minY +
                collectionView.frame.size.height - (keyboardFrame?.minY ?? 0) -
                collectionView.safeAreaInsets.bottom)
    }

    private func updateCollectionViewInsets(to newBottomInset: CGFloat, with info: KeyboardInfo) {
        let positionSnapshot = messagesLayout.getContentOffsetSnapshot(from: .bottom)

        if currentControllerActions.options.contains(.updatingCollection) {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates {}
            }
        }

        currentInterfaceActions.options.insert(.changingContentInsets)
        UIView.animate(withDuration: info.animationDuration, animations: {
            self.collectionView.performBatchUpdates({
                self.collectionView.contentInset.bottom = newBottomInset
                self.collectionView.verticalScrollIndicatorInsets.bottom = newBottomInset
            }, completion: nil)

            if let positionSnapshot, !self.isUserInitiatedScrolling {
                self.messagesLayout.restoreContentOffset(with: positionSnapshot)
            }
        }, completion: { _ in
            self.currentInterfaceActions.options.remove(.changingContentInsets)
        })
    }
}

// MARK: - MessageReactionMenuCoordinatorDelegate

extension MessagesViewController: MessageReactionMenuCoordinatorDelegate {
    func messageReactionMenuViewModel(_ coordinator: MessageReactionMenuCoordinator,
                                      for indexPath: IndexPath) -> MessageReactionMenuViewModel {
        MessageReactionMenuViewModel()
    }

    func messageReactionMenuCoordinatorWasPresented(_ coordinator: MessageReactionMenuCoordinator) {
        collectionView.isScrollEnabled = false
        currentInterfaceActions.options.insert(.showingReactionsMenu)
    }

    func messageReactionMenuCoordinatorWasDismissed(_ coordinator: MessageReactionMenuCoordinator) {
        collectionView.isScrollEnabled = true
        currentInterfaceActions.options.remove(.showingReactionsMenu)
    }

    func messageReactionMenuCoordinator(_ coordinator: MessageReactionMenuCoordinator,
                                        previewableCellAt indexPath: IndexPath) -> PreviewableCollectionViewCell? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? PreviewableCollectionViewCell else { return nil }
        return cell
    }

    func messageReactionMenuCoordinator(_ coordinator: MessageReactionMenuCoordinator,
                                        shouldPresentMenuFor cell: PreviewableCollectionViewCell) -> Bool {
        return true
    }
}
