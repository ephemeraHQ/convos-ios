# XMTP Test Infrastructure Setup - Summary

This document summarizes the Docker-based XMTP testing infrastructure that has been set up for convos-ios.

## What Was Created

### 1. Docker Infrastructure (`dev/`)

**Files Created:**
- `docker-compose.yml` - Docker Compose configuration for XMTP node
- `up` - Script to start Docker services
- `down` - Script to stop Docker services
- `compose` - Wrapper script for docker-compose commands
- `test` - Automated test runner script
- `README.md` - Documentation for the Docker setup

**Services:**
- XMTP Node (ports 5555, 5556)
- PostgreSQL database
- PostgreSQL MLS database
- MLS validation service

### 2. Test Configuration

**AppEnvironment.swift** - Updated to point `.tests` environment to `localhost` for Docker XMTP node

**ConvosConfiguration** - Already supports custom XMTP endpoints via `xmtpEndpoint` parameter

### 3. Test Helpers (`ConvosCore/Tests/ConvosCoreTests/TestHelpers.swift`)

**Created:**
- `TestConfig` - Test configuration and skip utilities
- `TestFixtures` - Actor for managing test XMTP clients
- `MockInvitesRepository` - Mock implementation of InvitesRepositoryProtocol
- `MockSyncingManager` - Mock implementation of SyncingManagerProtocol
- `SkipTest` - Error type for conditional test skipping
- Extensions for `MockDatabaseManager`

**Existing Mocks (Reused):**
- `MockKeychainIdentityStore` - Already exists in ConvosCore
- `MockDatabaseManager` - Already exists in ConvosCore

### 4. Comprehensive Test Suite (`ConvosCore/Tests/ConvosCoreTests/InboxStateMachineTests.swift`)

**Tests Created:**

**Registration Tests:**
- ✅ `testRegisterFlow` - Complete registration flow to ready state
- ✅ `testRegisterWithoutDatabaseSave` - Registration without DB persistence

**Authorization Tests:**
- ✅ `testAuthorizeFlow` - Authorize with existing identity
- ✅ `testAuthorizeMismatchedClientId` - Error handling for invalid clientId

**Stop Tests:**
- ✅ `testStopFlow` - Graceful shutdown transitions

**Delete Tests:**
- ✅ `testDeleteFlow` - Complete deletion with cleanup
- ✅ `testDeleteFromErrorState` - Deletion from error state

**State Observation Tests:**
- ✅ `testStateSequenceEmission` - State change observation
- ✅ `testActionQueueSequencing` - Action queue processing

### 5. GitHub Actions Workflow (`.github/workflows/inbox-state-machine-tests.yml`)

**Features:**
- Runs on macOS 26
- Starts Docker XMTP node automatically
- Waits for node to be ready
- Runs tests with `TEST_SERVER_ENABLED=true`
- Cleans up Docker containers
- Uploads test results as artifacts

**Triggers:**
- Pull requests affecting inbox code
- Pushes to main/dev branches
- Manual workflow dispatch

### 6. Documentation

**Created:**
- `dev/README.md` - Docker setup and troubleshooting guide
- `TESTING.md` - Comprehensive testing guide for developers

## How It Works

### Local Development

1. Developer runs `./dev/test` (or manually `./dev/up` + tests)
2. Docker starts XMTP node, PostgreSQL, and validation services
3. Tests create real XMTP clients connected to localhost:5556
4. InboxStateMachine is tested with real XMTP infrastructure
5. Docker containers are cleaned up after tests

### GitHub Actions

1. Workflow starts on PR/push
2. Docker installed on macOS runner
3. XMTP node started with health checks
4. Swift tests run with `TEST_SERVER_ENABLED=true`
5. Results uploaded as artifacts
6. Docker containers cleaned up

## Key Design Decisions

### 1. Real vs Mock XMTP Clients

**Approach:** Use real XMTP clients connected to local Docker node

**Rationale:**
- Tests the actual XMTP integration, not just mocks
- Catches real-world issues with XMTP client lifecycle
- Validates state machine behavior with actual async operations
- Similar to xmtp-ios approach (proven pattern)

### 2. Test Environment Configuration

**Approach:** `.tests` environment returns `"localhost"` for `xmtpEndpoint`

**Rationale:**
- Clean separation from dev/prod configurations
- No need to modify config files for tests
- Consistent with existing environment pattern

### 3. Mock Strategy

**Mocks Created:**
- `MockSyncingManager` - No real syncing needed for state machine tests
- `MockInvitesRepository` - Simplified invite storage
- `MockDatabaseManager` - In-memory SQLite (already existed)
- `MockKeychainIdentityStore` - In-memory keychain (already existed)

**Real Components:**
- XMTP clients (via Docker node)
- State machine logic
- Database operations (via in-memory SQLite)

### 4. Test Skipping

**Approach:** Tests skip if `TEST_SERVER_ENABLED != "true"`

**Rationale:**
- Allows running tests without Docker locally
- Clear error message when Docker not available
- Follows xmtp-ios pattern

## Similar to xmtp-ios Setup

This setup mirrors the xmtp-ios testing approach:

| Feature | xmtp-ios | convos-ios |
|---------|----------|------------|
| Docker XMTP node | ✅ | ✅ |
| PostgreSQL databases | ✅ | ✅ |
| MLS validation service | ✅ | ✅ |
| Port 5556 for tests | ✅ | ✅ |
| Skip tests without node | ✅ | ✅ |
| CI/CD integration | ✅ | ✅ |
| Test fixtures | ✅ | ✅ |

## What's Different

| Aspect | xmtp-ios | convos-ios |
|--------|----------|------------|
| Test framework | XCTest | Swift Testing |
| Test location | `Tests/XMTPTests/` | `ConvosCore/Tests/ConvosCoreTests/` |
| Environment config | `XMTPEnvironment.local` | `AppEnvironment.tests` |
| Database | Production DB | In-memory mock DB |
| Backend API | No backend | Mock ConvosAPI |

## Next Steps

### Immediate
1. Commit all files to git
2. Run tests locally to verify: `./dev/test`
3. Create a PR to trigger CI/CD workflow

### Future Enhancements
1. Add more test suites using this infrastructure:
   - `ConversationStateMachineTests`
   - `SyncingManagerTests`
   - Integration tests
2. Add performance benchmarks
3. Add test coverage reporting
4. Consider adding test parallelization

## Files Changed/Created

```
convos-ios/
├── dev/
│   ├── docker-compose.yml          [NEW]
│   ├── up                          [NEW]
│   ├── down                        [NEW]
│   ├── compose                     [NEW]
│   ├── test                        [NEW]
│   ├── README.md                   [NEW]
│   └── SETUP_SUMMARY.md            [NEW]
├── .github/workflows/
│   └── inbox-state-machine-tests.yml [NEW]
├── ConvosCore/
│   ├── Sources/ConvosCore/
│   │   └── AppEnvironment.swift    [MODIFIED]
│   └── Tests/ConvosCoreTests/
│       ├── TestHelpers.swift       [NEW]
│       └── InboxStateMachineTests.swift [NEW]
└── TESTING.md                      [NEW]
```

## Verification Checklist

- [x] Docker compose configuration created
- [x] Scripts are executable
- [x] AppEnvironment.swift updated for tests
- [x] Test helpers and mocks created
- [x] Comprehensive test suite created
- [x] GitHub Actions workflow created
- [x] Documentation created
- [ ] Tests run successfully locally
- [ ] Tests run successfully in CI/CD
- [ ] Code reviewed and merged

## Resources

- XMTP node: https://github.com/xmtp/xmtp-node-go
- Docker Compose: https://docs.docker.com/compose/
- Swift Testing: https://github.com/apple/swift-testing
- Reference: xmtp-ios `dev/local/` setup
