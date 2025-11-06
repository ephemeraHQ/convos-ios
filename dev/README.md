# Local XMTP Node for Testing

This directory contains Docker Compose configuration for running a local XMTP node for testing.

## Architecture

The Docker setup includes:
- **XMTP Node**: Main XMTP node (ports 5555, 5556)
- **PostgreSQL**: Database for message storage
- **PostgreSQL MLS**: Database for MLS (group messaging) storage
- **MLS Validation Service**: Validates MLS operations

## Usage

### Start the local XMTP node

```bash
./dev/up
```

This will:
1. Pull the latest XMTP Docker images
2. Start all services in detached mode
3. Expose ports 5555 and 5556 for XMTP connections

### Stop the local XMTP node

```bash
./dev/down
```

### Direct Docker Compose commands

```bash
# View logs
./dev/compose logs -f

# Check status
./dev/compose ps

# Restart services
./dev/compose restart
```

## Running Tests

### Locally

1. Start the XMTP node:
   ```bash
   ./dev/up
   ```

2. Run the tests with the test server enabled:
   ```bash
   xcodebuild test \
     -project Convos.xcodeproj \
     -scheme ConvosCore \
     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' \
     -only-testing:ConvosCoreTests/InboxStateMachineTests \
     TEST_SERVER_ENABLED=true
   ```

3. Stop the XMTP node when done:
   ```bash
   ./dev/down
   ```

### In CI/CD

Tests are automatically run in GitHub Actions with the local XMTP node. See `.github/workflows/inbox-state-machine-tests.yml`.

## Configuration

The test environment (`.tests`) in `AppEnvironment.swift` is configured to:
- Use `localhost` as the XMTP endpoint
- Connect to port 5556 (non-secure)
- Use temporary directories for databases

## Troubleshooting

### Node fails to start

Check the logs:
```bash
./dev/compose logs node
```

Common issues:
- Port 5555 or 5556 already in use
- Docker not running
- Insufficient Docker resources

### Tests timeout

Ensure the node is fully ready before running tests. You can check connectivity:
```bash
nc -z localhost 5556 && echo "XMTP node is ready" || echo "XMTP node is not ready"
```

### Clean slate

To completely reset the environment:
```bash
./dev/down
docker volume prune  # Remove all unused volumes
./dev/up
```

## Port Reference

- **5555**: XMTP gRPC API
- **5556**: XMTP gRPC API (used by tests)
- **5432**: PostgreSQL (internal to Docker network)
