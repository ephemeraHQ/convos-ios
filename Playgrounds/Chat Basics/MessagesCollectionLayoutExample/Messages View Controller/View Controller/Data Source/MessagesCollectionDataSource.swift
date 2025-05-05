import Foundation
import UIKit

protocol MessagesCollectionDataSource: UICollectionViewDataSource, MessagesLayoutDelegate {
    var sections: [Section] { get set }
    func prepare(with collectionView: UICollectionView)
}
