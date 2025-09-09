# Environment Configuration

## Overview

The app supports 3 environments with distinct configurations:

| Environment | XMTP Network | Backend | Main Bundle ID | Purpose |
|-------------|--------------|---------|----------------|---------|
| **Local** | XMTP Local | localhost:4000 | `org.convos.ios-local` | Development with local XMTP |
| **Dev** | XMTP Dev | api.convos-otr-dev.convos-api.xyz | `org.convos.ios-preview` | TestFlight builds, real XMTP dev |
| **Production** | XMTP Prod | api.convos-otr-prod.convos-api.xyz | `org.convos.ios` | App Store release |

### Complete Bundle ID Structure

| Target | Local | Dev | Production |
|--------|-------|-----|------------|
| **Main App** | `org.convos.ios-local` | `org.convos.ios-preview` | `org.convos.ios` |
| **Tests** | `org.convos.ios-local.tests` | `org.convos.ios-preview.tests` | `org.convos.ios.tests` |
| **App Clip** | `org.convos.ios-local.Clip` | `org.convos.ios-preview.Clip` | `org.convos.ios.Clip` |
| **App Clip Tests** | `org.convos.ios-local.ConvosAppClipTests` | `org.convos.ios-preview.ConvosAppClipTests` | `org.convos.ios.ConvosAppClipTests` |
| **Notification Service** | `org.convos.ios-local.ConvosNSE` | `org.convos.ios-preview.ConvosNSE` | `org.convos.ios.ConvosNSE` |

## How Environment Switching Works

### 🏗️ Build-Time Selection
- **Xcode Build Configurations** determine which environment to use
- **`.xcconfig` files** set `CONFIG_FILE` variable per environment
- **Build script** copies the correct `config.json` to app bundle
- **`ConfigManager`** loads config at runtime and tells `AppEnvironment` what to use

### 📁 File Structure
```
Convos/Config/
├── config.local.json     # Local development settings
├── config.dev.json       # TestFlight/staging settings
├── config.prod.json      # Production settings
├── Local.xcconfig        # Build settings for local
├── Dev.xcconfig          # Build settings for dev
├── Prod.xcconfig         # Build settings for prod
└── Secrets.swift         # Generated from .env (sensitive data)

Scripts/
└── copy-config.sh        # Copies correct config per build
```

## 🔄 How to Switch Environments

### Method 1: Xcode Scheme (Recommended)
1. **Create 3 schemes** in Xcode:
   - `Convos Local` → Uses Debug config → Copies `config.local.json`
   - `Convos Dev` → Uses Dev config → Copies `config.dev.json`
   - `Convos Prod` → Uses Release config → Copies `config.prod.json`

2. **Switch environment:**
   - Xcode toolbar → Select scheme dropdown
   - Choose `Convos Local`, `Convos Dev`, or `Convos Prod`
   - Build and run

### Method 2: Build Configuration
1. **Product** → **Scheme** → **Edit Scheme**
2. **Run** tab → **Info** → **Build Configuration**
3. Select: `Debug` (local), `Dev`, or `Release` (prod)

## ⚙️ Setup Instructions

### 1. Add Build Configurations
1. Open **Convos.xcodeproj**
2. **Project** → **Info** → **Configurations**
3. **Duplicate** "Debug" → Rename to "Dev"
4. You should have: `Debug`, `Dev`, `Release`

### 2. Assign .xcconfig Files
1. **Project** → **Info** → **Configurations**
2. For **ALL targets** (Convos, ConvosTests, ConvosAppClip, ConvosAppClipTests, NotificationService):
   - **Debug** → Select `Convos/Config/Local.xcconfig`
   - **Dev** → Select `Convos/Config/Dev.xcconfig`
   - **Release** → Select `Convos/Config/Prod.xcconfig`

### 2.1. Set Target-Specific Bundle IDs
After assigning `.xcconfig` files, update each target's bundle ID:

1. **Convos target** → Build Settings → Product Bundle Identifier → `$(CONVOS_BUNDLE_ID)`
2. **ConvosTests target** → Build Settings → Product Bundle Identifier → `$(CONVOS_TESTS_BUNDLE_ID)`
3. **ConvosAppClip target** → Build Settings → Product Bundle Identifier → `$(CONVOS_APP_CLIP_BUNDLE_ID)`
4. **ConvosAppClipTests target** → Build Settings → Product Bundle Identifier → `$(CONVOS_APP_CLIP_TESTS_BUNDLE_ID)`
5. **NotificationService target** → Build Settings → Product Bundle Identifier → `$(NOTIFICATION_SERVICE_BUNDLE_ID)`

### 3. Add Build Phase Script
1. **Target** → **Build Phases** → **+ New Run Script Phase**
2. **Name:** "Copy Environment Config"
3. **Script:** `"${SRCROOT}/Scripts/copy-config.sh"`
4. **Move** this phase to run **before** "Compile Sources"

### 4. Create Schemes (Optional but Recommended)
1. **Product** → **Scheme** → **New Scheme**
2. Create:
   - **Convos Local** (Debug config)
   - **Convos Dev** (Dev config)
   - **Convos Prod** (Release config)

## 🔍 Verification

After setup, you can verify environment switching works:

```swift
// Add this to ConvosApp.swift init() for testing
print("🏃 Running in: \(ConfigManager.shared.currentEnvironment.rawValue)")
print("🌐 Backend: \(ConfigManager.shared.backendURLOverride ?? "default")")
```

## 🚨 Important Notes

- **Secrets stay in `.env`** → `Secrets.swift` (not in config JSON)
- **Config files are tracked in Git** (no sensitive data!)
- **Bundle IDs differ per environment** (allows side-by-side installation)
- **All environments use real XMTP networks** (local/dev/production)
- **Build script fails fast** if config file missing

## 🛠️ Development Workflow

### Typical Usage:
- **Daily dev work:** Use `Convos Local` scheme
- **TestFlight builds:** Use `Convos Dev` scheme
- **App Store release:** Use `Convos Prod` scheme

### CI/CD Integration:
```bash
# Bitrise can build specific schemes
xcodebuild -scheme "Convos Dev" -configuration Dev archive
xcodebuild -scheme "Convos Prod" -configuration Release archive
```

## 🧪 Testing Environments

You can test environment switching without Xcode setup:

1. **Manually copy a config:**
   ```bash
   cp Convos/Config/config.dev.json Convos/Config/config.json
   ```

2. **Add config.json to Xcode project** (temporary)

3. **Build and run** - should load dev environment

4. **Remove config.json** when done testing
