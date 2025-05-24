import SwiftUI

struct DropdownMenuSection: Identifiable {
    let id: UUID = UUID()
    let items: [DropdownMenuItem]
}

struct DropdownMenuItem: Identifiable {
    let id: UUID = UUID()
    let title: String
    let subtitle: String?
    let icon: Image?
    let isSelected: Bool
    let isIdentity: Bool
    let action: () -> Void
}

struct DropdownMenu: View {
    let sections: [DropdownMenuSection]
    let onDismiss: () -> Void

    @State private var animateIn: Bool = false

    var body: some View {
        ZStack {
            // Dismiss overlay
            Color.black.opacity(animateIn ? 0.15 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .animation(.easeInOut(duration: 0.18), value: animateIn)

            VStack(spacing: 0) {
                ForEach(sections.indices, id: \ .self) { sectionIndex in
                    let section = sections[sectionIndex]
                    VStack(spacing: 0) {
                        ForEach(section.items.indices, id: \ .self) { itemIndex in
                            let item = section.items[itemIndex]
                            DropdownMenuRow(item: item)
                            if itemIndex < section.items.count - 1 {
                                Spacer().frame(height: 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if sectionIndex < sections.count - 1 {
                        Spacer().frame(height: 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            )
            //            .frame(width: 260, height: nil, alignment: .center)
            .frame(minWidth: 260, idealWidth: nil, maxWidth: 260, alignment: .center)
            .padding(.horizontal, 16)
            .scaleEffect(animateIn ? 1 : 0.95, anchor: .top)
            .opacity(animateIn ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: animateIn)
        }
        .onAppear { animateIn = true }
    }
}

struct DropdownMenuRow: View {
    let item: DropdownMenuItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let icon = item.icon {
                icon
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.secondary)
            }
            if item.isIdentity && item.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            item.action()
        }
    }
}

#Preview {
    DropdownMenu(
        sections: [
            DropdownMenuSection(items: [
                DropdownMenuItem(
                    title: "Convos", subtitle: "All chats", icon: nil, isSelected: true, isIdentity: true, action: {}
                ),
                DropdownMenuItem(
                    title: "Andrew", subtitle: nil, icon: nil, isSelected: false, isIdentity: true, action: {}
                ),
                DropdownMenuItem(
                    title: "Incognito", subtitle: nil, icon: nil, isSelected: false, isIdentity: true, action: {}
                )
            ]),
            DropdownMenuSection(items: [
                DropdownMenuItem(
                    title: "New Contact Card",
                    subtitle: nil,
                    icon: Image("contactCard"),
                    isSelected: false,
                    isIdentity: false,
                    action: {}
                ),
            ]),
            DropdownMenuSection(items: [
                DropdownMenuItem(
                    title: "App Settings",
                    subtitle: nil,
                    icon: Image("gear"),
                    isSelected: false,
                    isIdentity: false,
                    action: {}
                )
            ])
        ],
        onDismiss: {}
    )
}
