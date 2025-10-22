#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# This script generates the Secrets.swift file for Local development
# It automatically detects the local IP address and populates the secrets
# It also ensures the file exists with minimal content if needed
# Usage: ./generate-secrets-local.sh

# The path to the Secrets.swift file
SECRETS_FILE="Convos/Config/Secrets.swift"

# Create the output directory if it doesn't exist
mkdir -p "Convos/Config"

# Function to create minimal Secrets.swift if it doesn't exist or is empty
ensure_minimal_secrets() {
    if [ ! -f "$SECRETS_FILE" ] || [ ! -s "$SECRETS_FILE" ]; then
        echo "🔑 Creating minimal Secrets.swift file first"

        cat >"$SECRETS_FILE" <<'MINIMAL_EOF'
import Foundation

// WARNING:
// This is a minimal Secrets.swift file created automatically.
// Building the "Convos (Local)" scheme will replace this with auto-detected IP addresses.

// swiftlint:disable all

enum Secrets {
    static let CONVOS_API_BASE_URL: String = ""
    static let XMTP_CUSTOM_HOST: String = ""
}

// swiftlint:enable all
MINIMAL_EOF
        echo "✅ Created minimal Secrets.swift file"
        return 0
    fi
    return 1
}

# If called with --ensure-only flag, just ensure minimal file exists and exit
if [ "$1" = "--ensure-only" ]; then
    if ensure_minimal_secrets; then
        echo "✅ Minimal Secrets.swift created - ready for building"
    else
        echo "✅ Secrets.swift already exists"
    fi
    exit 0
fi

echo "🔍 Detecting configuration for Local development..."

# Ensure minimal file exists first (in case this is the first run)
ensure_minimal_secrets || true  # Don't exit if file already exists

# Function to get the first routable IPv4 address
get_local_ip() {
    # Get all network interfaces and find the first routable IPv4 address
    # Exclude:
    # - 127.x.x.x (loopback)
    # - 169.254.x.x (link-local/APIPA - indicates DHCP failure)
    # - 0.0.0.0 (invalid)
    # Prefer in order:
    # 1. Public IP addresses (not in private ranges)
    # 2. Private network addresses (10.x.x.x, 172.16-31.x.x, 192.168.x.x)

    # First try to get a public IP (not in private ranges)
    local public_ip=$(ifconfig | grep -E "inet [0-9]+" | \
        grep -v "127\." | \
        grep -v "169\.254\." | \
        grep -v "10\." | \
        grep -v "172\.1[6-9]\." | \
        grep -v "172\.2[0-9]\." | \
        grep -v "172\.3[0-1]\." | \
        grep -v "192\.168\." | \
        head -1 | awk '{print $2}')

    if [ -n "$public_ip" ]; then
        echo "$public_ip"
        return
    fi

    # If no public IP, get the first private network IP (but not link-local)
    local private_ip=$(ifconfig | grep -E "inet [0-9]+" | \
        grep -v "127\." | \
        grep -v "169\.254\." | \
        head -1 | awk '{print $2}')

    echo "$private_ip"
}

# Function to extract value from config JSON
get_config_value() {
    local config_file=$1
    local key=$2
    if [ -f "$config_file" ]; then
        # Use python to parse JSON (available on macOS by default)
        python3 -c "import json; print(json.load(open('$config_file')).get('$key', ''))" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Load defaults from config.local.json
CONFIG_FILE="Convos/Config/config.local.json"
DEFAULT_BACKEND_URL=$(get_config_value "$CONFIG_FILE" "backendUrl")

# Detect the local IP for auto-configuration
LOCAL_IP=$(get_local_ip)

# Read .env overrides if they exist
ENV_BACKEND_URL=""
ENV_XMTP_HOST=""

if [ -f ".env" ]; then
    echo "📋 Checking .env for overrides..."
    # Check for uncommented values in .env
    ENV_BACKEND_URL=$(grep -v '^#' ".env" | grep '^CONVOS_API_BASE_URL=' | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' || true)
    ENV_XMTP_HOST=$(grep -v '^#' ".env" | grep '^XMTP_CUSTOM_HOST=' | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' || true)
fi

# Determine final values (priority: .env override > auto-detected IP > config.json default > empty)
FINAL_BACKEND_URL=""
FINAL_XMTP_HOST=""

# CONVOS_API_BASE_URL logic
if [ -n "$ENV_BACKEND_URL" ]; then
    FINAL_BACKEND_URL="$ENV_BACKEND_URL"
    echo "✅ Using CONVOS_API_BASE_URL from .env: $FINAL_BACKEND_URL"
elif [ -n "$LOCAL_IP" ]; then
    FINAL_BACKEND_URL="http://$LOCAL_IP:4000/api"
    echo "✅ Auto-detected CONVOS_API_BASE_URL: $FINAL_BACKEND_URL"
elif [ -n "$DEFAULT_BACKEND_URL" ]; then
    FINAL_BACKEND_URL="$DEFAULT_BACKEND_URL"
    echo "✅ Using CONVOS_API_BASE_URL from config.json: $FINAL_BACKEND_URL"
else
    FINAL_BACKEND_URL=""
    echo "⚠️  CONVOS_API_BASE_URL will be empty"
fi

# XMTP_CUSTOM_HOST logic
if [ -n "$ENV_XMTP_HOST" ]; then
    FINAL_XMTP_HOST="$ENV_XMTP_HOST"
    echo "✅ Using XMTP_CUSTOM_HOST from .env: $FINAL_XMTP_HOST"
elif [ -n "$LOCAL_IP" ]; then
    FINAL_XMTP_HOST="$LOCAL_IP"
    echo "✅ Auto-detected XMTP_CUSTOM_HOST: $FINAL_XMTP_HOST"
else
    FINAL_XMTP_HOST=""
    echo "⚠️  XMTP_CUSTOM_HOST will be empty"
fi

echo "🔑 Generating $SECRETS_FILE for Local development"

# Generate Secrets.swift with determined values
cat >"$SECRETS_FILE" <<EOF
import Foundation

// WARNING:
// This code is generated by ./Scripts/generate-secrets-local.sh for Local development.
// Do not edit this file directly. Your changes will be lost on next build.
// Git does not track this file.
// Priority: .env overrides > auto-detected IP > config.json defaults > empty string
// For other environments, edit the .env file and run ./Scripts/generate-secrets.sh

// swiftlint:disable all

/// Secrets are generated automatically for Local development
enum Secrets {
    static let CONVOS_API_BASE_URL: String = "$FINAL_BACKEND_URL"
    static let XMTP_CUSTOM_HOST: String = "$FINAL_XMTP_HOST"
EOF

# Check if .env file exists and add any additional secrets from it
if [ -f ".env" ]; then
    echo "📋 Adding additional secrets from .env file..."

    # Read each line from .env file, handles missing newline at EOF
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue

        # Skip the keys we already handled
        [[ "$key" == "CONVOS_API_BASE_URL" ]] && continue
        [[ "$key" == "XMTP_CUSTOM_HOST" ]] && continue

        # Remove any quotes from the value
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//')

        # Add the secret to the Swift file
        echo "    static let $key: String = \"$value\"" >>"$SECRETS_FILE"
    done <.env
else
    echo "⚠️  No .env file found, using defaults from config.json"
fi

# Close the enum and add SwiftLint enable comment
cat >>"$SECRETS_FILE" <<'EOF'
}

// swiftlint:enable all
EOF

echo "🏁 Generated $SECRETS_FILE successfully"
echo "🔗 CONVOS_API_BASE_URL: $FINAL_BACKEND_URL"
echo "🌐 XMTP_CUSTOM_HOST: $FINAL_XMTP_HOST"
