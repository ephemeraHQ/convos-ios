import ConvosCore
import Foundation
import SwiftUI
import UIKit

// swiftlint:disable force_cast

final class MessagesCollectionViewDataSource: NSObject {
    var sections: [MessagesCollectionSection] = [] {
        didSet {
            layoutDelegate = DefaultMessagesLayoutDelegate(sections: sections,
                                                           oldSections: layoutDelegate.sections)
        }
    }

    var onTapAvatar: ((IndexPath) -> Void)?
    var onTapInvite: ((MessageInvite) -> Void)?

    private lazy var layoutDelegate: DefaultMessagesLayoutDelegate = DefaultMessagesLayoutDelegate(sections: sections,
                                                                                                   oldSections: [])

    private func registerCells(in collectionView: UICollectionView) {
        collectionView.register(ConversationInfoCell.self,
                                forCellWithReuseIdentifier: ConversationInfoCell.reuseIdentifier)
        collectionView.register(TextMessageCollectionCell.self,
                                forCellWithReuseIdentifier: TextMessageCollectionCell.reuseIdentifier)
        collectionView.register(MessageInviteCell.self, forCellWithReuseIdentifier: MessageInviteCell.reuseIdentifier)
        collectionView.register(ImageCollectionCell.self,
                                forCellWithReuseIdentifier: ImageCollectionCell.reuseIdentifier)
        collectionView.register(InviteCell.self, forCellWithReuseIdentifier: InviteCell.reuseIdentifier)

        collectionView.register(UserTitleCollectionCell.self,
                                forCellWithReuseIdentifier: UserTitleCollectionCell.reuseIdentifier)
        collectionView.register(TypingIndicatorCollectionCell.self,
                                forCellWithReuseIdentifier: TypingIndicatorCollectionCell.reuseIdentifier)
        collectionView.register(TextTitleCell.self,
                                forCellWithReuseIdentifier: TextTitleCell.reuseIdentifier)

        collectionView.register(TextTitleView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: TextTitleView.reuseIdentifier)
        collectionView.register(TextTitleView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: TextTitleView.reuseIdentifier)
    }
}

extension MessagesCollectionViewDataSource: MessagesCollectionDataSource {
    func prepare(with collectionView: UICollectionView) {
        registerCells(in: collectionView)
    }
}

extension MessagesCollectionViewDataSource: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].cells.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = sections[indexPath.section].cells[indexPath.item]
        return CellFactory.createCell(in: collectionView, for: indexPath, with: item, onTapInvite: { [weak self] invite in
            Log.info("Tapped invite: \(invite)")
            self?.onTapInvite?(invite)
        }, onTapAvatar: { [weak self] in
            self?.onTapAvatar?(indexPath)
        })
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: TextTitleView.reuseIdentifier,
            for: indexPath
        ) as! TextTitleView
        view.setup(title: sections[indexPath.section].title)
        return view
    }
}

extension MessagesCollectionViewDataSource: MessagesLayoutDelegate {
    func shouldPresentHeader(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        layoutDelegate.shouldPresentHeader(messagesLayout, at: sectionIndex)
    }

    func shouldPresentFooter(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        layoutDelegate.shouldPresentFooter(messagesLayout, at: sectionIndex)
    }

    func sizeForItem(_ messagesLayout: MessagesCollectionLayout,
                     of kind: ItemKind,
                     at indexPath: IndexPath) -> ItemSize {
        layoutDelegate.sizeForItem(messagesLayout, of: kind, at: indexPath)
    }

    func alignmentForItem(_ messagesLayout: MessagesCollectionLayout,
                          of kind: ItemKind,
                          at indexPath: IndexPath) -> MessagesCollectionCell.Alignment {
        layoutDelegate.alignmentForItem(messagesLayout, of: kind, at: indexPath)
    }

    func initialLayoutAttributesForInsertedItem(_ messagesLayout: MessagesCollectionLayout,
                                                of kind: ItemKind,
                                                at indexPath: IndexPath,
                                                modifying originalAttributes: MessagesLayoutAttributes,
                                                on state: InitialAttributesRequestType) {
        layoutDelegate.initialLayoutAttributesForInsertedItem(messagesLayout,
                                                              of: kind,
                                                              at: indexPath,
                                                              modifying: originalAttributes,
                                                              on: state)
    }

    func finalLayoutAttributesForDeletedItem(_ messagesLayout: MessagesCollectionLayout,
                                             of kind: ItemKind,
                                             at indexPath: IndexPath,
                                             modifying originalAttributes: MessagesLayoutAttributes) {
        layoutDelegate.finalLayoutAttributesForDeletedItem(messagesLayout,
                                                           of: kind,
                                                           at: indexPath,
                                                           modifying: originalAttributes)
    }

    func interItemSpacing(_ messagesLayout: MessagesCollectionLayout,
                          of kind: ItemKind,
                          after indexPath: IndexPath) -> CGFloat? {
        layoutDelegate.interItemSpacing(messagesLayout, of: kind, after: indexPath)
    }

    func interSectionSpacing(_ messagesLayout: MessagesCollectionLayout,
                             after sectionIndex: Int) -> CGFloat? {
        layoutDelegate.interSectionSpacing(messagesLayout, after: sectionIndex)
    }
}

// swiftlint:enable force_cast
