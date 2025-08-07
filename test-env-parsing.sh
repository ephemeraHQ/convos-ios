#!/bin/bash
set -e

SRCROOT="$(pwd)"
SECRETS_FILE="test-secrets.swift"

# Generate Secrets.swift with auto-detected IP
cat >"$SECRETS_FILE" <<INNER_EOF
import Foundation
enum Secrets {
    static let CONVOS_API_BASE_URL = "http://172.20.10.4:4000/api"
    static let XMTP_CUSTOM_HOST = "172.20.10.4"
INNER_EOF

# Add other secrets from .env if available
if [ -f "${SRCROOT}/.env" ]; then
    echo "📋 Adding additional secrets from .env file..."
    
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        # Skip the IP-related keys since we're auto-generating them
        [[ "$key" == "CONVOS_API_BASE_URL" ]] && continue
        [[ "$key" == "XMTP_CUSTOM_HOST" ]] && continue
        
        # Remove any quotes from the value
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//')
        
        # Add the secret to the Swift file
        echo "    static let $key = \"$value\"" >>"$SECRETS_FILE"
    done <"${SRCROOT}/.env"
fi

# Close the enum
cat >>"$SECRETS_FILE" <<'CLOSE_EOF'
}
CLOSE_EOF

echo "Generated test file:"
cat "$SECRETS_FILE"
