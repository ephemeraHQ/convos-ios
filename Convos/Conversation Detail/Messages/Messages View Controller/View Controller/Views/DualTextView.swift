import SwiftUI
import UIKit

// MARK: - DualTextView

class DualTextView: UIView {
    let textView: UITextView = UITextView()
    let textField: UITextField = UITextField()
    private let textViewPlaceholderLabel: UILabel = UILabel()
    private var currentMode: Mode = .textView {
        didSet {
            updateVisibility()
        }
    }

    enum Mode {
        case textView
        case textField
    }

    var mode: Mode {
        get { currentMode }
        set {
            currentMode = newValue
            // Automatically become first responder when switching modes
            DispatchQueue.main.async {
                _ = self.becomeFirstResponder()
            }
        }
    }

    weak var textViewDelegate: UITextViewDelegate?

    var textViewText: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updateTextViewPlaceholder()
            invalidateIntrinsicContentSize()
        }
    }

    var textFieldText: String {
        get { textField.text ?? "" }
        set {
            textField.text = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var textViewPlaceholder: String? {
        get { textViewPlaceholderLabel.text }
        set {
            textViewPlaceholderLabel.text = newValue
            updateTextViewPlaceholder()
        }
    }

    var textFieldPlaceholder: String? {
        get { textField.placeholder }
        set { textField.placeholder = newValue }
    }

    var font: UIFont? {
        get { textView.font }
        set {
            textView.font = newValue
            textField.font = newValue
            textViewPlaceholderLabel.font = newValue
        }
    }

    var textColor: UIColor? {
        get { textView.textColor }
        set {
            textView.textColor = newValue
            textField.textColor = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Configure textView
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 0.0, left: 0, bottom: 0.0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        addSubview(textView)

        // Configure textView placeholder label
        textViewPlaceholderLabel.textColor = .placeholderText
        textViewPlaceholderLabel.numberOfLines = 0
        textViewPlaceholderLabel.isUserInteractionEnabled = false
        addSubview(textViewPlaceholderLabel)

        // Configure textField
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.addTarget(
            self,
            action: #selector(Self.textFieldDidChange(_:)),
            for: .editingChanged
        )
        addSubview(textField)

        // Set initial visibility
        updateVisibility()
    }

    private func updateVisibility() {
        textView.isHidden = currentMode != .textView
        textField.isHidden = currentMode != .textField
        updateTextViewPlaceholder()
    }

    private func updateTextViewPlaceholder() {
        textViewPlaceholderLabel.isHidden = !textView.text.isEmpty || currentMode != .textView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Both views take up the entire bounds
        textView.frame = bounds
        textField.frame = bounds

        // Position placeholder label to match textView's text container
        let textContainerInset = textView.textContainerInset
        let lineFragmentPadding = textView.textContainer.lineFragmentPadding
        textViewPlaceholderLabel.frame = CGRect(
            x: textContainerInset.left + lineFragmentPadding,
            y: textContainerInset.top,
            width: bounds.width - textContainerInset.left - textContainerInset.right - lineFragmentPadding * 2,
            height: bounds.height - textContainerInset.top - textContainerInset.bottom
        )
    }

    override var intrinsicContentSize: CGSize {
        let size: CGSize
        switch currentMode {
        case .textView:
            let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .infinity))
            size = CGSize(width: UIView.noIntrinsicMetric, height: textSize.height)
        case .textField:
            let textSize = textField.sizeThatFits(CGSize(width: bounds.width, height: .infinity))
            size = CGSize(width: UIView.noIntrinsicMetric, height: textSize.height)
        }
        return size
    }

    override var canBecomeFirstResponder: Bool {
        switch currentMode {
        case .textView:
            return textView.canBecomeFirstResponder
        case .textField:
            return textField.canBecomeFirstResponder
        }
    }

    override func becomeFirstResponder() -> Bool {
        switch currentMode {
        case .textView:
            return textView.becomeFirstResponder()
        case .textField:
            return textField.becomeFirstResponder()
        }
    }

    override func resignFirstResponder() -> Bool {
        let textViewResigned = textView.resignFirstResponder()
        let textFieldResigned = textField.resignFirstResponder()
        return textViewResigned || textFieldResigned
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        invalidateIntrinsicContentSize()
    }
}

// MARK: - DualTextView Delegates

extension DualTextView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateTextViewPlaceholder()
        invalidateIntrinsicContentSize()
        textViewDelegate?.textViewDidChange?(textView)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        textViewDelegate?.textViewDidBeginEditing?(textView)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        textViewDelegate?.textViewDidEndEditing?(textView)
    }
}

// MARK: - SwiftUI Wrapper

struct DualTextViewRepresentable: UIViewRepresentable {
    @Binding var textViewText: String
    @Binding var textFieldText: String
    @Binding var mode: DualTextView.Mode
    @Binding var height: CGFloat
    let textViewPlaceholder: String?
    let textFieldPlaceholder: String?
    let font: UIFont?
    let textColor: UIColor?

    init(
        textViewText: Binding<String>,
        textFieldText: Binding<String>,
        mode: Binding<DualTextView.Mode>,
        height: Binding<CGFloat>,
        textViewPlaceholder: String? = nil,
        textFieldPlaceholder: String? = nil,
        font: UIFont? = nil,
        textColor: UIColor? = nil
    ) {
        self._textViewText = textViewText
        self._textFieldText = textFieldText
        self._mode = mode
        self._height = height
        self.textViewPlaceholder = textViewPlaceholder
        self.textFieldPlaceholder = textFieldPlaceholder
        self.font = font
        self.textColor = textColor
    }

    func makeUIView(context: Context) -> DualTextView {
        let view = DualTextView()
        view.textViewPlaceholder = textViewPlaceholder
        view.textFieldPlaceholder = textFieldPlaceholder
        view.font = font
        view.textColor = textColor
        view.textViewDelegate = context.coordinator
        view.textField
            .addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
        return view
    }

    func updateUIView(_ uiView: DualTextView, context: Context) {
        uiView.textViewText = textViewText
        uiView.textFieldText = textFieldText
        uiView.mode = mode

        DispatchQueue.main.async {
            height = uiView.intrinsicContentSize.height
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let parent: DualTextViewRepresentable

        init(_ parent: DualTextViewRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.textViewText = textView.text ?? ""
            DispatchQueue.main.async { [weak self] in
                if let dualTextView = textView.superview as? DualTextView {
                    self?.parent.height = dualTextView.intrinsicContentSize.height
                }
            }
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            parent.textFieldText = textField.text ?? ""
            DispatchQueue.main.async { [weak self] in
                if let dualTextView = textField.superview as? DualTextView {
                    self?.parent.height = dualTextView.intrinsicContentSize.height
                }
            }
        }
    }
}

// MARK: - SwiftUI View

struct DualTextInputView: View {
    @State private var textViewText: String = ""
    @State private var textFieldText: String = ""
    @State private var mode: DualTextView.Mode = .textView
    @State private var currentHeight: CGFloat = 44

    var body: some View {
        VStack {
            DualTextViewRepresentable(
                textViewText: $textViewText,
                textFieldText: $textFieldText,
                mode: $mode,
                height: $currentHeight,
                textViewPlaceholder: "Enter long text here...",
                textFieldPlaceholder: "Enter short text here...",
                font: .systemFont(ofSize: 16),
                textColor: .label
            )
            .frame(height: max(44, currentHeight))
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            HStack {
                Button("Show TextView") {
                    mode = .textView
                }
                .disabled(mode == .textView)

                Button("Show TextField") {
                    mode = .textField
                }
                .disabled(mode == .textField)
            }
            .padding()

            VStack(alignment: .leading) {
                Text("TextView text: \(textViewText)")
                Text("TextField text: \(textFieldText)")
                Text("Current height: \(currentHeight, specifier: "%.1f")")
            }
            .padding()
        }
    }
}

#if DEBUG
#Preview {
    DualTextInputView()
}
#endif
