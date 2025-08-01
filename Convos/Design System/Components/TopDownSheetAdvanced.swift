import SwiftUI

// MARK: - Configuration

struct TopDownSheetConfiguration {
    var height: CGFloat = 100
    var cornerRadius: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    var shadowRadius: CGFloat = 10
    var backgroundOpacity: Double = 0.3
    var dismissOnBackgroundTap: Bool = true
    var dismissOnSwipeUp: Bool = true
    var showDragIndicator: Bool = false
}

// MARK: - Advanced TopDownSheet View Modifier

struct TopDownSheetAdvancedModifier<SheetContent: View, BackgroundContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: TopDownSheetConfiguration
    @ViewBuilder let sheetContent: () -> SheetContent
    @ViewBuilder let backgroundContent: (Content) -> BackgroundContent

    @State private var offset: CGFloat = -200
    @State private var opacity: Double = 0
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging: Bool = false

    private var totalOffset: CGFloat {
        offset + dragOffset
    }

    func body(content: Content) -> some View {
        ZStack {
            if isPresented {
                // Custom background content
                backgroundContent(content)
                    .opacity(opacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if configuration.dismissOnBackgroundTap {
                            dismiss()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(0)
            } else {
                content
                    .zIndex(0)
            }

            if isPresented {
                // Top-down sheet content
                VStack {
                    VStack(spacing: 0) {
                        if configuration.showDragIndicator {
                            // Drag indicator
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 36, height: 5)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                        }

                        self.sheetContent()
                            .frame(height: configuration.height - (configuration.showDragIndicator ? 25 : 0))
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: configuration.cornerRadius)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(
                                color: .black.opacity(0.13),
                                radius: configuration.shadowRadius,
                                x: 0,
                                y: 4.0
                            )
                    )
                    .padding(.horizontal, configuration.horizontalPadding)
                    .offset(y: totalOffset)
                    .opacity(opacity)
                    .onTapGesture { } // Prevent dismissal when tapping content
                    .gesture(
                        configuration.dismissOnSwipeUp ? swipeGesture : nil
                    )

                    Spacer()
                }
                .padding(.top, 60.0) // @jarodl get the actual safe area
                .transition(.asymmetric(insertion: .identity, removal: .identity))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                show()
            } else {
                hide()
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // Only allow upward swipes
                if value.translation.height < 0 {
                    dragOffset = value.translation.height * 0.5 // Reduce sensitivity
                }
            }
            .onEnded { value in
                // If swiped up enough, dismiss
                if value.translation.height < -50 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func show() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            offset = 0
            opacity = 1
        }
    }

    private func hide() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            offset = -200
            opacity = 0
        }
    }

    private func dismiss() {
        isPresented = false
        dragOffset = 0
    }
}

// MARK: - View Extensions

extension View {
    /// Presents a modal sheet that slides down from the top of the screen with default configuration
    func topDownSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(TopDownSheetAdvancedModifier<Content, AnyView>(
            isPresented: isPresented,
            configuration: TopDownSheetConfiguration(),
            sheetContent: content,
            backgroundContent: { originalContent in
                AnyView(
                    ZStack {
                        originalContent
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                    }
                )
            }
        ))
    }

    /// Presents a modal sheet that slides down from the top of the screen with custom configuration
    func topDownSheet<Content: View>(
        isPresented: Binding<Bool>,
        configuration: TopDownSheetConfiguration,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(TopDownSheetAdvancedModifier<Content, AnyView>(
            isPresented: isPresented,
            configuration: configuration,
            sheetContent: content,
            backgroundContent: { originalContent in
                AnyView(
                    ZStack {
                        originalContent
                        Color.black.opacity(configuration.backgroundOpacity)
                            .ignoresSafeArea()
                    }
                )
            }
        ))
    }

    /// Presents a modal sheet that slides down from the top of the screen with custom background
    func topDownSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        configuration: TopDownSheetConfiguration = TopDownSheetConfiguration(),
        @ViewBuilder backgroundContent: @escaping (Self) -> some View,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(TopDownSheetAdvancedModifier<SheetContent, AnyView>(
            isPresented: isPresented,
            configuration: configuration,
            sheetContent: content,
            backgroundContent: { _ in
                AnyView(backgroundContent(self))
            }
        ))
    }
}

// MARK: - Preview

#Preview("Default Configuration") {
    struct PreviewView: View {
        @State private var isPresented: Bool = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Default Top Down Sheet")
                    .font(.largeTitle)

                Button("Show Sheet") {
                    isPresented = true
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .topDownSheet(isPresented: $isPresented) {
                HStack(spacing: 16) {
                    Image(systemName: "info.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)

                    Text("This is a notification message")
                        .font(.body)

                    Spacer()
                }
                .padding()
            }
        }
    }

    return PreviewView()
}

#Preview("Custom Configuration") {
    struct PreviewView: View {
        @State private var isPresented: Bool = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Custom Top Down Sheet")
                    .font(.largeTitle)

                Button("Show Custom Sheet") {
                    isPresented = true
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .topDownSheet(
                isPresented: $isPresented,
                configuration: TopDownSheetConfiguration(
                    height: 120,
                    cornerRadius: 20,
                    horizontalPadding: 24,
                    shadowRadius: 15,
                    backgroundOpacity: 0.5,
                    dismissOnBackgroundTap: true,
                    dismissOnSwipeUp: true,
                    showDragIndicator: true
                )
            ) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Success!")
                                .font(.headline)
                            Text("Swipe up to dismiss")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }
                .padding()
            }
        }
    }

    return PreviewView()
}
