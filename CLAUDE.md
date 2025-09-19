# Convos iOS - Codebase Best Practices

This document contains project-specific conventions and best practices for the Convos iOS codebase.

## Architecture & Organization

### Project Structure
- **Main App**: SwiftUI app with UIKit integration where needed
- **ConvosCore**: Swift Package containing core business logic, storage, and XMTP client
- **App Clips**: Separate target for lightweight experiences
- **Notification Service**: Extension for push notification handling

### Module Architecture
- Use `ConvosCore` for shared business logic, models, and services
- Keep UI-specific code in the main app target
- Use protocols for dependency injection (e.g., `SessionManagerProtocol`)

## SwiftUI Conventions

### State Management
- **Modern Observation Framework**: Use `@Observable` with `@State` for new code
  ```swift
  @Observable
  class MyViewModel {
      var property: String = ""
  }

  // In views:
  @State private var viewModel = MyViewModel()
  ```
- Legacy code may still use `ObservableObject` with `@StateObject`/@ObservedObject`

### Button Pattern
Always extract button actions to avoid closure compilation errors:
```swift
// ✅ Good
let action = { /* action code */ }
Button(action: action) {
    // view content
}

// ❌ Bad - causes compilation issues
Button(action: { /* action */ }) {
    // view content
}
```

### Preview Support
Use `@Previewable` for preview state variables:
```swift
@Previewable @State var text: String = "Preview"
```

## Code Style & Formatting

### SwiftFormat Configuration
- Trim whitespace always
- Use closure-only for stripping unused arguments
- Braces follow K&R style, opening brace on the same line (not Allman)
- Trailing commas in multi-line collections and parameter lists

### SwiftLint Rules
Key enforced rules:
- No force unwrapping
- Prefer `first(where:)` over filter operations
- Use explicit types for public interfaces
- Sort imports alphabetically
- Private over fileprivate
- No implicitly unwrapped optionals

### Naming Conventions
- ViewModels: `ConversationViewModel`, `ProfileViewModel`
- Views: `ConversationsView`, `MessageView`
- Storage: `SceneURLStorage`, `DatabaseManager`
- Repositories: `ConversationsCountRepository`
- Use descriptive names over abbreviations

## Dependency Management

### Swift Package Manager (SPM)
All dependencies managed through SPM. See `ConvosCore/Package.swift` for current versions.

### Environment Configuration
- Use `ConfigManager` for environment-specific settings
- Environments: Production, Development, Local
- Firebase configuration per environment

## Deep Linking

### URL Handling Architecture
- `SceneURLStorage`: Coordinates URL handling between SceneDelegate and SwiftUI
- `ConvosSceneDelegate`: Handles both Universal Links and custom URL schemes
- `DeepLinkHandler`: Validates and processes deep links
- Store pending URLs for cold launch scenarios

## Logging & Debugging

### Logger Configuration
```swift
Logger.configure(environment: environment)
Logger.info("Message")
Logger.error("Error message")
```
- Production vs development logging levels
- Environment-specific configuration

## Testing Conventions

### Mock Data
- Use `.mock` static methods for preview/test data
- Example: `ConversationViewModel.mock`

### Test Organization
- Unit tests in `ConvosTests`
- Core logic tests in `ConvosCoreTests`
- UI tests in separate target

## Security Best Practices

- Never commit secrets or API keys
- Use environment variables for sensitive configuration
- Validate all deep links before processing
- Use Firebase App Check for API protection

## Performance Guidelines

### Image Handling
- Use `AvatarView` with built-in caching
- Lazy load images where appropriate
- Handle image state (loading, loaded, error)

### SwiftUI Performance
- Use `@MainActor` for UI-related classes
- Minimize view body complexity
- Extract complex views into separate components

## Build & Release

### Build Commands
```bash
# Check for linting issues
swiftlint

# Auto-fix linting issues
swiftlint --fix

# Format code
swiftformat .

# Run tests (Local environment on iOS Simulator)
xcodebuild test -scheme "Convos (Local)" -destination "platform=iOS Simulator,name=iPhone 17"

# Build for device (Local environment)
xcodebuild build -scheme "Convos (Local)" -configuration Debug

# Clean build folder
xcodebuild clean -scheme "Convos (Local)"
```

### Xcode Project Settings
- Minimum iOS version: 26.0
- Swift language mode: 5
- Single project structure with local SPM packages

## Migration Guidelines

### ObservableObject to @Observable
When migrating from `ObservableObject`:
1. Remove `ObservableObject` conformance
2. Add `@Observable` macro and `import Observation`
3. Remove `@Published` property wrappers
4. Change `@StateObject`/`@ObservedObject` to `@State` in views

## Important Notes

- **No trailing whitespace** on any lines
- **Don't add comments** unless specifically requested
- **Prefer editing existing files** over creating new ones
- **Follow existing patterns** in neighboring code
- **Check dependencies** before using any library
