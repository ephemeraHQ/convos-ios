import SwiftUI

// MARK: - Example Usage in Convos App

struct TopDownSheetDemoView: View {
    @State private var showSuccessNotification: Bool = false
    @State private var showErrorNotification: Bool = false
    @State private var showCustomNotification: Bool = false
    @State private var showTextInputSheet: Bool = false
    @State private var showBlurredBackgroundSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Success Notification Example
                Button {
                    showSuccessNotification = true
                } label: {
                    Label("Show Success Notification", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                // Error Notification Example
                Button {
                    showErrorNotification = true
                } label: {
                    Label("Show Error Notification", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                                // Custom Notification Example
                Button {
                    showCustomNotification = true
                } label: {
                    Label("Show Custom Notification", systemImage: "bell")
                }
                .buttonStyle(.borderedProminent)

                // Text Input Example
                Button {
                    showTextInputSheet = true
                } label: {
                    Label("Show Text Input", systemImage: "keyboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                // Blurred Background Example
                Button {
                    showBlurredBackgroundSheet = true
                } label: {
                    Label("Show with Blurred Background", systemImage: "camera.filters")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Spacer()
            }
            .padding()
            .navigationTitle("Top Down Sheet Demo")
            .background(Color("colorBackgroundPrimary"))
        }
        // Success notification
        .topDownSheet(isPresented: $showSuccessNotification) {
            SuccessNotificationContent()
        }
        // Error notification
        .topDownSheet(
            isPresented: $showErrorNotification,
            configuration: TopDownSheetConfiguration(
                height: 80,
                backgroundOpacity: 0.4
            )
        ) {
            ErrorNotificationContent()
        }
        // Custom notification with drag indicator
        .topDownSheet(
            isPresented: $showCustomNotification,
            configuration: TopDownSheetConfiguration(
                height: 140,
                cornerRadius: 20,
                horizontalPadding: 20,
                showDragIndicator: true
            )
        ) {
            CustomNotificationContent()
        }
        // Text input sheet with auto-focus
        .topDownSheet(
            isPresented: $showTextInputSheet,
            configuration: TopDownSheetConfiguration(
                height: 100,
                dismissOnBackgroundTap: true,
                dismissOnSwipeUp: false // Disable swipe up to avoid conflicts with keyboard
            )
        ) {
            TextInputSheetContent(isPresented: $showTextInputSheet)
        }
        // Blurred background sheet
        .topDownSheet(
            isPresented: $showBlurredBackgroundSheet,
            configuration: TopDownSheetConfiguration(
                height: 120,
                cornerRadius: 24,
                horizontalPadding: 20,
                dismissOnBackgroundTap: true,
                dismissOnSwipeUp: true,
                showDragIndicator: true
            ),
            backgroundContent: { originalContent in
                originalContent
                    .blur(radius: 10)
                    .overlay(
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                    )
            },
            content: {
                BlurredBackgroundSheetContent()
            })
    }
}

// MARK: - Notification Content Examples

struct SuccessNotificationContent: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Message Sent")
                    .font(.headline)
                Text("Your message was delivered successfully")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}

struct ErrorNotificationContent: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.red)

            Text("Failed to send message")
                .font(.body)

            Spacer()
        }
        .padding()
    }
}

struct CustomNotificationContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProfileAvatarView(
                    profile: Profile(
                        inboxId: "demo",
                        name: "John Doe",
                        username: "johndoe",
                        avatar: nil
                    )
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New message from John Doe")
                        .font(.headline)
                    Text("Hey! Are you available for a call?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Reply") {
                    // Handle reply
                }
                .buttonStyle(.bordered)

                Button("Mark as Read") {
                    // Handle mark as read
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct TextInputSheetContent: View {
    @Binding var isPresented: Bool
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search or enter text...", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    // Handle submit action
                    isPresented = false
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button("Done") {
                isPresented = false
            }
            .font(.body.weight(.medium))
        }
        .padding()
        .onAppear {
            // Auto-focus the text field when the sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
}

struct BlurredBackgroundSheetContent: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.filters")
                .font(.largeTitle)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Blurred Background Effect")
                .font(.headline)

            Text("The background content is customizable!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Integration Example in ConversationView

struct ConversationViewWithTopDownSheet: View {
    @State private var showOffTheRecordNotification: Bool = false

    var body: some View {
        VStack {
            // Your conversation content here
            Text("Conversation Content")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Example: Show notification when toggling off-the-record mode
            Button("Toggle Off-The-Record") {
                showOffTheRecordNotification = true
                // Your off-the-record logic here
            }
            .padding()
        }
        .topDownSheet(isPresented: $showOffTheRecordNotification) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Off-The-Record Mode")
                        .font(.headline)
                    Text("Messages won't be saved in this mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    showOffTheRecordNotification = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

#Preview("Demo View") {
    TopDownSheetDemoView()
}

#Preview("Conversation Integration") {
    ConversationViewWithTopDownSheet()
}
