import Foundation
import UIKit

protocol KeyboardListenerDelegate: AnyObject {
    func keyboardWillShow(info: KeyboardInfo)
    func keyboardDidShow(info: KeyboardInfo)
    func keyboardWillHide(info: KeyboardInfo)
    func keyboardDidHide(info: KeyboardInfo)
    func keyboardWillChangeFrame(info: KeyboardInfo)
    func keyboardDidChangeFrame(info: KeyboardInfo)
}

extension KeyboardListenerDelegate {
    func keyboardWillShow(info: KeyboardInfo) {}
    func keyboardDidShow(info: KeyboardInfo) {}
    func keyboardWillHide(info: KeyboardInfo) {}
    func keyboardDidHide(info: KeyboardInfo) {}
    func keyboardWillChangeFrame(info: KeyboardInfo) {}
    func keyboardDidChangeFrame(info: KeyboardInfo) {}
}

final class KeyboardListener {
    static let shared: KeyboardListener = KeyboardListener()
    private(set) var keyboardRect: CGRect?
    private var delegates: NSHashTable<AnyObject> = NSHashTable<AnyObject>.weakObjects()

    // Fallback support
    private var pendingDidChangeFrameInfo: KeyboardInfo?
    private var didChangeFrameTimer: Timer?

    func add(delegate: KeyboardListenerDelegate) {
        delegates.add(delegate)
    }

    func remove(delegate: KeyboardListenerDelegate) {
        delegates.remove(delegate)
    }

    private init() {
        subscribeToKeyboardNotifications()
    }

    @objc
    private func keyboardWillShow(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        keyboardRect = info.frameEnd
        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardWillShow(info: info)
        }
    }

    @objc
    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        keyboardRect = info.frameEnd
        pendingDidChangeFrameInfo = info

        // Cancel any existing timer
        didChangeFrameTimer?.invalidate()

        // Start a fallback timer slightly longer than the expected duration
        didChangeFrameTimer = Timer.scheduledTimer(withTimeInterval: info.animationDuration + 0.1, repeats: false) { [weak self] _ in
            self?.handleMissingDidChangeFrame()
        }

        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardWillChangeFrame(info: info)
        }
    }

    @objc
    private func keyboardDidChangeFrame(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        // Cancel the fallback timer
        didChangeFrameTimer?.invalidate()
        didChangeFrameTimer = nil
        pendingDidChangeFrameInfo = nil

        keyboardRect = info.frameEnd
        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardDidChangeFrame(info: info)
        }
    }

    @objc
    private func keyboardDidShow(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        keyboardRect = info.frameEnd
        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardDidShow(info: info)
        }
    }

    @objc
    private func keyboardWillHide(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        keyboardRect = info.frameEnd
        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardWillHide(info: info)
        }
    }

    @objc
    private func keyboardDidHide(_ notification: Notification) {
        guard let info = KeyboardInfo(notification) else {
            return
        }

        keyboardRect = info.frameEnd
        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardDidHide(info: info)
        }
    }

    private func handleMissingDidChangeFrame() {
        guard let info = pendingDidChangeFrameInfo else { return }

        keyboardRect = info.frameEnd
        pendingDidChangeFrameInfo = nil
        didChangeFrameTimer = nil

        delegates.allObjects.compactMap { $0 as? KeyboardListenerDelegate }.forEach {
            $0.keyboardDidChangeFrame(info: info)
        }
    }

    private func subscribeToKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidShow(_:)),
                                               name: UIResponder.keyboardDidShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidHide(_:)),
                                               name: UIResponder.keyboardDidHideNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidChangeFrame(_:)),
                                               name: UIResponder.keyboardDidChangeFrameNotification,
                                               object: nil)
    }
}
