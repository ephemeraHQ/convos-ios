import Combine
import Foundation
import UIKit
import DifferenceKit

final class MessagesViewController: UIViewController {
    // MARK: - Types

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
    }

    private enum ControllerActions {
        case loadingInitialMessages
        case loadingPreviousMessages
        case updatingCollection
    }

    // MARK: - UIViewController Overrides

    override var inputAccessoryView: UIView? {
        inputBarView
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    // MARK: - Properties

    private var currentInterfaceActions: SetActor<Set<InterfaceActions>, ReactionTypes> = SetActor()
    private var currentControllerActions: SetActor<Set<ControllerActions>, ReactionTypes> = SetActor()

    private var collectionView: UICollectionView!
    private var messagesLayout = MessagesCollectionLayout()
    private let inputBarView = MessagesInputView()
    private let navigationBar = MessagesNavigationBar(frame: .zero)

    private let messagingService: MessagingServiceProtocol
    private let dataSource: MessagesCollectionDataSource

    private var animator: ManualAnimator?

    private var isUserInitiatedScrolling: Bool {
        collectionView.isDragging || collectionView.isDecelerating
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(messagingService: MessagingServiceProtocol) {
        self.messagingService = messagingService
        self.dataSource = MessagesCollectionViewDataSource()
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
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

    // MARK: - Lifecycle Methods

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent != nil else { return }
        becomeFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarHidden(true, animated: false)

        setupCollectionView()
        setupInputBar()
        loadInitialData()
        setupUI()

        messagingService.updates.receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                processUpdates(
                    with: update.sections,
                    animated: true,
                    requiresIsolatedProcess: update.requiresIsolatedProcess
                )
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        handleViewTransition(to: size, with: coordinator)
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ensureInputBarVisibility()

        // Update navigation bar frame to include safe area
        navigationBar.frame = CGRect(
            x: view.bounds.origin.x,
            y: view.bounds.origin.y,
            width: view.bounds.width,
            height: MessagesNavigationBar.Constants.height + view.safeAreaInsets.top
        )

        // Set content inset to just the base navigation bar height
        collectionView.contentInset.top = MessagesNavigationBar.Constants.height
        collectionView.verticalScrollIndicatorInsets.top = collectionView.contentInset.top
    }

    // MARK: - Private Setup Methods

    private func setupUI() {
        view.backgroundColor = .systemBackground
        navigationBar.leftButton.setImage(
            UIImage(systemName: "chevron.left",
                    withConfiguration: UIImage.SymbolConfiguration(weight: .medium)),
            for: .normal)
        navigationBar.rightButton.setImage(
            UIImage(systemName: "timer",
                    withConfiguration: UIImage.SymbolConfiguration(weight: .medium)),
            for: .normal)
        navigationBar.configure(title: "Terry Gross", avatar: nil)
        view.addSubview(navigationBar)
    }

    private func setupCollectionView() {
        configureMessagesLayout()
        setupCollectionViewInstance()
        configureCollectionViewConstraints()
        configureCollectionViewBehavior()
    }

    private func configureMessagesLayout() {
        messagesLayout.settings.interItemSpacing = 8
        messagesLayout.settings.interSectionSpacing = 8
        messagesLayout.settings.additionalInsets = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        messagesLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        messagesLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
    }

    private func setupCollectionViewInstance() {
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: messagesLayout)
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

        // TODO: https://openradar.appspot.com/40926834
        collectionView.isPrefetchingEnabled = false

        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.automaticallyAdjustsScrollIndicatorInsets = true
        collectionView.selfSizingInvalidation = .enabled
        messagesLayout.supportSelfSizingInvalidation = true

        dataSource.prepare(with: collectionView)
    }

    private func setupInputBar() {
        inputBarView.delegate = self
        inputBarView.translatesAutoresizingMaskIntoConstraints = false
        KeyboardListener.shared.add(delegate: self)
    }

    private func loadInitialData() {
        currentControllerActions.options.insert(.loadingInitialMessages)
        Task {
            let sections = await messagingService.loadInitialMessages()
            currentControllerActions.options.remove(.loadingInitialMessages)
            processUpdates(with: sections, animated: true, requiresIsolatedProcess: false)
        }
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

    private func ensureInputBarVisibility() {
        if inputBarView.superview == nil,
           topMostViewController() is MessagesViewController {
            DispatchQueue.main.async { [weak self] in
                self?.reloadInputViews()
            }
        }
    }

    // MARK: - Scrolling Methods

    private func loadPreviousMessages() {
        currentControllerActions.options.insert(.loadingPreviousMessages)
        Task {
            let sections = await messagingService.loadPreviousMessages()
            let animated = !isUserInitiatedScrolling
            processUpdates(with: sections, animated: animated, requiresIsolatedProcess: true) {
                self.currentControllerActions.options.remove(.loadingPreviousMessages)
            }
        }
    }

    func scrollToBottom(completion: (() -> Void)? = nil) {
        let contentOffsetAtBottom = CGPoint(x: collectionView.contentOffset.x,
                                            y: messagesLayout.collectionViewContentSize.height - collectionView.frame.height + collectionView.adjustedContentInset.bottom)

        guard contentOffsetAtBottom.y > collectionView.contentOffset.y else {
            completion?()
            return
        }

        performScrollToBottom(from: contentOffsetAtBottom, initialOffset: collectionView.contentOffset.y, completion: completion)
    }

    private func performScrollToBottom(from contentOffsetAtBottom: CGPoint, initialOffset: CGFloat, completion: (() -> Void)?) {
        let delta = contentOffsetAtBottom.y - initialOffset

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
    private func processUpdates(with sections: [Section],
                                animated: Bool = true,
                                requiresIsolatedProcess: Bool,
                                completion: (() -> Void)? = nil) {
        guard isViewLoaded else {
            dataSource.sections = sections
            return
        }

        guard currentInterfaceActions.options.isEmpty else {
            scheduleDelayedUpdate(with: sections, animated: animated, requiresIsolatedProcess: requiresIsolatedProcess, completion: completion)
            return
        }

        performUpdate(with: sections, animated: animated, requiresIsolatedProcess: requiresIsolatedProcess, completion: completion)
    }

    private func scheduleDelayedUpdate(with sections: [Section],
                                       animated: Bool,
                                       requiresIsolatedProcess: Bool,
                                       completion: (() -> Void)?) {
        let reaction = SetActor<Set<InterfaceActions>, ReactionTypes>.Reaction(
            type: .delayedUpdate,
            action: .onEmpty,
            executionType: .once,
            actionBlock: { [weak self] in
                guard let self else { return }
                processUpdates(with: sections,
                               animated: animated,
                               requiresIsolatedProcess: requiresIsolatedProcess,
                               completion: completion)
            })
        currentInterfaceActions.add(reaction: reaction)
    }

    private func performUpdate(with sections: [Section],
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

        if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + scrollView.bounds.height {
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

// MARK: - MessagesInputViewDelegate

extension MessagesViewController: MessagesInputViewDelegate {
    func messagesInputView(_ view: MessagesInputView, didChangeIntrinsicContentSize size: CGSize) {
        guard !currentInterfaceActions.options.contains(.sendingMessage) else { return }
        scrollToBottom()
    }

    func messagesInputView(_ view: MessagesInputView, didTapSend text: String) {
        currentInterfaceActions.options.insert(.sendingMessage)
        scrollToBottom()
        Task {
            let sections = await messagingService.sendMessage(.text(text))
            currentInterfaceActions.options.remove(.sendingMessage)
            processUpdates(with: sections, animated: true, requiresIsolatedProcess: false)
        }
    }

    func messagesInputView(_ view: MessagesInputView, didChangeText text: String) {
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

    func keyboardWillHide(info: KeyboardInfo) {
        becomeFirstResponder()
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
        return collectionView.frame.minY + collectionView.frame.size.height - (keyboardFrame?.minY ?? 0) - collectionView.safeAreaInsets.bottom
    }

    private func updateCollectionViewInsets(to newBottomInset: CGFloat, with info: KeyboardInfo) {
        let positionSnapshot = messagesLayout.getContentOffsetSnapshot(from: .bottom)

        if currentControllerActions.options.contains(.updatingCollection) {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates({})
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
