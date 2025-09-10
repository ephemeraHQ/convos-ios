# Fastlane Setup for Convos iOS

This document explains the Fastlane configuration for building and deploying the Convos iOS app.

## Overview

We've switched from raw `xcodebuild` commands to **Fastlane** for better:
- **Code Signing Management**: Automatic handling of certificates and provisioning profiles
- **Error Handling**: Clear error messages and better debugging
- **TestFlight Integration**: Seamless uploads with proper metadata
- **Industry Standards**: Using the same tools as most iOS teams

## Fastlane Lanes

### `fastlane ios test`
- Runs unit tests on iPhone 16 simulator
- Uses `Convos (Dev)` scheme with `Dev` configuration

### `fastlane ios dev`
- Builds development version (`org.convos.ios-preview`)
- Uses `Convos (Dev)` scheme with `Dev` configuration
- Exports with `app-store-connect` method
- Uploads to TestFlight automatically

### `fastlane ios prod`
- Builds production version (`org.convos.ios`)
- Uses `Convos (Prod)` scheme with `Prod` configuration
- Exports with `app-store-connect` method
- Uploads to TestFlight automatically

## Required Secrets

### GitHub Repository Secrets
```bash
# App Store Connect API Authentication
APP_STORE_CONNECT_API_KEY_ID=ABC123DEF4
APP_STORE_CONNECT_ISSUER_ID=12345678-1234-1234-1234-123456789012
APP_STORE_CONNECT_API_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----...-----END PRIVATE KEY-----
APP_STORE_CONNECT_TEAM_ID=1234567890

# Other App Secrets (from your generate-secrets-secure.sh)
FIREBASE_APP_CHECK_TOKEN=your_firebase_token
TURNKEY_PUBLIC_ORGANIZATION_ID=your_turnkey_org_id
TURNKEY_API_PUBLIC_KEY=your_turnkey_public_key
TURNKEY_API_PRIVATE_KEY=your_turnkey_private_key
```

### GitHub Repository Variables
```bash
# Build Configuration
BASE_BUILD_NUMBER=1000
XCODE_PROJECT=Convos.xcodeproj
DEVELOPER_TEAM_ID=FY4NZR34Z3
```

## How Fastlane Handles Signing

1. **API Key Authentication**: Uses App Store Connect API key for secure access
2. **Automatic Profile Download**: Downloads latest provisioning profiles before build using `get_provisioning_profile`
3. **Certificate Management**: Uses certificates already in your App Store Connect account
4. **Multi-Target Support**: Handles main app, notification service extension, and app clip automatically
5. **Environment-Specific**: Downloads correct profiles based on dev/prod environment

### Code Signing Flow

```
before_all (CI only)
├── setup_code_signing
│   ├── app_store_connect_api_key (authenticate)
│   ├── get_provisioning_profile (main app)
│   ├── get_provisioning_profile (NSE)
│   └── get_provisioning_profile (app clip)
└── build_app (with automatic signing)

## Benefits Over Raw Xcodebuild

| Feature | Raw Xcodebuild | Fastlane |
|---------|---------------|----------|
| Code Signing | Manual setup required | Automatic |
| Error Messages | Cryptic | Clear and actionable |
| TestFlight Upload | Manual `altool` commands | Built-in |
| Multi-Target Builds | Complex scripting | Handled automatically |
| Build Number Management | Manual `agvtool` | Automatic increment |

## Local Testing

To test Fastlane locally:

```bash
# Install dependencies
bundle install

# Test development build (don't upload)
bundle exec fastlane ios dev --env development

# Test production build (don't upload)
bundle exec fastlane ios prod --env development
```

## Troubleshooting

### Common Issues

1. **"No profiles found"**: Check App Store Connect API key permissions
2. **"Certificate not found"**: Ensure certificates exist in App Store Connect
3. **"Invalid bundle ID"**: Verify bundle IDs match your App Store Connect apps

### Debug Commands

```bash
# Check Fastlane environment
bundle exec fastlane env

# List available actions
bundle exec fastlane actions

# Verbose output
bundle exec fastlane ios dev --verbose
```

## Migration from Bitrise

Key changes from the original Bitrise setup:

1. **Build Number Setting**: Now handled by Fastlane's `increment_build_number`
2. **Code Signing**: Automatic instead of manual profile management
3. **Upload**: Direct TestFlight integration instead of separate `altool` commands
4. **Multi-Target**: Single command handles all targets (main app, NSE, app clip)

The build numbers remain sequential and unique across environments using the same `BASE_BUILD_NUMBER + github.run_number` formula.
