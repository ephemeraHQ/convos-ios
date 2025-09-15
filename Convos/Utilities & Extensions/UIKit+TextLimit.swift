import UIKit

extension UITextField {
    func convos_setMaxLength(_ n: Int) {
        addTarget(self, action: #selector(limitText), for: .editingChanged)
        tag = n // Store max length in tag
    }

    @objc private func limitText() {
        guard let text = text, text.count > tag else { return }
        self.text = String(text.prefix(tag))
    }
}
