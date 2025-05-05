#!/bin/bash

# This script generates the entitlements file from .env
# Usage: ./generate_entitlements.sh

ENTITLEMENTS_FILE="Convos/Convos.entitlements"

echo "🔑 Generating $ENTITLEMENTS_FILE"

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Error: .env file not found"
    exit 1
fi

# Get RP_ID from .env
API_RP_ID=$(grep API_RP_ID .env | cut -d '=' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/"//g')

if [ -z "$API_RP_ID" ]; then
    echo "Error: API_RP_ID not found in .env"
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "$(dirname "$ENTITLEMENTS_FILE")"

# Generate the entitlements file
cat > "$ENTITLEMENTS_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>webcredentials:$API_RP_ID?mode=developer</string>
        <string>applinks:$API_RP_ID?mode=developer</string>
    </array>
</dict>
</plist>
EOF

echo "🏁 Generated $ENTITLEMENTS_FILE" 