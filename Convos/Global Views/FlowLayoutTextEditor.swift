import SwiftUI

struct FlowLayoutTextEditor: View {
    @Binding var text: String
    @Binding var editingEnabled: Bool
    @FocusState private var isFocused: Bool
    let maxTextFieldWidth: CGFloat
    let minTextFieldWidth: CGFloat = 75.0
    let onBackspaceWhenEmpty: () -> Void

    var body: some View {
        Group {
            BackspaceTextField(text: $text,
                               editingEnabled: $editingEnabled,
                               onBackspaceWhenEmpty: onBackspaceWhenEmpty)
                .font(.system(size: 14.0))
                .tint(.colorTextPrimary)
                .padding(.horizontal, 10.0)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .padding(.vertical, DesignConstants.Spacing.step2x)
                .frame(maxWidth: maxTextFieldWidth)
                .truncationMode(.head)
                .lineLimit(1)
                .focused($isFocused)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: minTextFieldWidth, alignment: .leading)
        .clipped()
        .onAppear {
            isFocused = true
        }
        .onTapGesture {
            isFocused = true
        }
    }
}

private struct FlowLayoutTextEditorExample: View {
    let maxHeight: CGFloat = 150.0

    @State var searchText: String = ""
    @State var editingEnabled: Bool = true
    @State var selectedItem: String? {
        didSet {
            editingEnabled = selectedItem == nil
        }
    }
    @State var items: [String] = [
        "Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Cameron", "Skylar",
        "Emerson", "Quinn", "Avery", "Hayden", "Rowan", "Sage", "Finley", "Dakota",
        "Madison", "Reese", "Logan", "Phoenix", "Artemis", "VeryLongNameThatWillWrapNicely",
        "VeryLongNameThatWillNotFitInTheWidthOfTheEntireViewAndWillTruncate",
        "John"
    ]

    func selected(item: String) {
        selectedItem = selectedItem == item ? nil : item
    }

    func backspaceOnEmpty() {
        if let selectedItem {
            items.removeAll { $0 == selectedItem }
            self.selectedItem = nil
        } else {
            selectedItem = items.last
        }
    }

    var body: some View {
        GeometryReader { reader in
            ScrollView {
                FlowLayout(spacing: DesignConstants.Spacing.step2x) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .foregroundStyle(item == selectedItem ? .colorTextPrimaryInverted : .colorTextPrimary)
                            .padding(DesignConstants.Spacing.step2x)
                            .background(item == selectedItem ? .colorBackgroundInverted : .gray.opacity(0.2))
                            .cornerRadius(DesignConstants.CornerRadius.small)
                    }

                    FlowLayoutTextEditor(text: $searchText,
                                         editingEnabled: $editingEnabled,
                                         maxTextFieldWidth: reader.size.width) {
                        backspaceOnEmpty()
                    }
                                         .opacity(selectedItem != nil ? 0.0 : 1.0)
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: maxHeight)
        }
        .frame(maxHeight: maxHeight)
    }
}

#Preview {
    VStack {
        HStack {
            Spacer().frame(width: 40.0)
            FlowLayoutTextEditorExample()
            Spacer().frame(width: 40.0)
        }
        Spacer()
    }
}
