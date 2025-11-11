import SwiftUI

// This exists to get around the selected state for Profile "chips"
// needing to go outside the scroll view clipping area
struct VerticalEdgeClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.minX - (rect.width / 2.0),
                            y: rect.minY,
                            width: rect.width * 2.0,
                            height: rect.height))
        return path
    }
}

@Observable
class TagsFieldViewModel {
    var currentText: String = ""
    private(set) var tags: [String]
    var selectedTag: String?

    init(tags: [String]) {
        self.currentText = ""
        self.tags = tags
    }

    func addCurrentTag() {
        let trimmedTag = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTag = trimmedTag.lowercased()

        guard !canonicalTag.isEmpty else { return }

        guard !tags.contains(where: { $0.lowercased() == canonicalTag }) else {
            currentText = ""
            return
        }

        currentText = ""
        tags.append(canonicalTag)
    }

    func remove(tag: String) {
        tags.removeAll(where: { $0 == tag })
    }
}

struct TagsField: View {
    let viewModel: TagsFieldViewModel
    @State private var tagHeight: CGFloat = 0.0
    @Binding var currentText: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    @Binding var selectedTag: String? {
        didSet {
            textEditingEnabled = selectedTag == nil
        }
    }
    @State var textEditingEnabled: Bool = true

    private let tagMaxHeight: CGFloat = 150.0

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: DesignConstants.Spacing.step2x) {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            ChipView(tag: tag,
                                     isSelected: selectedTag == tag)
                            .tag(tag)
                            .onTapGesture {
                                selected(tag: tag)
                            }
                            .offset(y: 0.0)
                        }

                        FlowLayoutTextEditor(
                            text: $currentText,
                            editingEnabled: $textEditingEnabled,
                            isFocused: isTextFieldFocused,
                            maxTextFieldWidth: reader.size.width,
                            onBackspaceWhenEmpty: {
                                backspaceOnEmpty()
                            },
                            onReturn: {
                                viewModel.addCurrentTag()
                            },
                            onEndedEditing: {
                                selectedTag = nil
                            }
                        )
                        .id("textField")
                        .padding(.bottom, 0.0)
                        .opacity(selectedTag != nil ? 0.0 : 1.0)
                    }
                    .padding(.vertical, DesignConstants.Spacing.step4x)
                    .background(HeightReader())
                    .onPreferenceChange(HeightPreferenceKey.self) { height in
                        tagHeight = min(height, tagMaxHeight)
                    }
                    .padding(.top, 0.0)
                    .onChange(of: selectedTag) {
                        if let id = selectedTag {
                            isTextFieldFocused.wrappedValue = true
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: currentText) {
                        textChanged(currentText)
                        if tagHeight >= tagMaxHeight {
                            withAnimation {
                                proxy.scrollTo("textField", anchor: .center)
                            }
                        }
                    }
                    .scrollBounceBehavior(.always)
                }
                .scrollClipDisabled()
                .clipShape(VerticalEdgeClipShape())
            }
        }
        .frame(height: tagHeight)
    }

    func selected(tag: String) {
        selectedTag = selectedTag == tag ? nil : tag
    }

    func backspaceOnEmpty() {
        if let selectedTag {
            viewModel.remove(tag: selectedTag)
            self.selectedTag = nil
        } else {
            selectedTag = viewModel.tags.last
        }
    }

    func textChanged(_ text: String) {
    }
}

#Preview {
    @Previewable @State var viewModel: TagsFieldViewModel = TagsFieldViewModel(tags: ["Testing 1", "Testing 2"])
    @Previewable @FocusState var textFieldFocusState: Bool

    VStack {
        HStack {
            Spacer().frame(width: 40)
            TagsField(
                viewModel: viewModel,
                currentText: $viewModel.currentText,
                isTextFieldFocused: $textFieldFocusState,
                selectedTag: $viewModel.selectedTag
            )
            Spacer().frame(width: 40)
        }
        Text("Content Below")

        Spacer()
    }
}
