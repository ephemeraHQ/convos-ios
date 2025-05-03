import Foundation

protocol MessagesControllerDelegate: AnyObject {
    func update(with sections: [Section], requiresIsolatedProcess: Bool)
}
