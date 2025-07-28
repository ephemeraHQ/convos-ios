#!/usr/bin/env bash

# Copy environment-specific config.json to app bundle
# Usage: Called automatically by Xcode build phase

set -e

# Get config file from build settings (set in .xcconfig)
CONFIG_SOURCE="${SRCROOT}/Convos/Config/${CONFIG_FILE}"
CONFIG_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/config.json"

if [ ! -f "$CONFIG_SOURCE" ]; then
    echo "❌ Error: Config file not found: $CONFIG_SOURCE"
    echo "   Make sure CONFIG_FILE is set in your .xcconfig"
    exit 1
fi

echo "📋 Copying config: $CONFIG_FILE → config.json"
cp "$CONFIG_SOURCE" "$CONFIG_DEST"

echo "✅ Config copied successfully"