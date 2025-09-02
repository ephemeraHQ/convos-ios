#!/bin/bash

set -e
set -o pipefail

# Get the version from Xcode project
VERSION=$(grep -o 'MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;' Convos.xcodeproj/project.pbxproj | head -1 | sed 's/MARKETING_VERSION = \([0-9]*\.[0-9]*\.[0-9]*\);/\1/')

echo "🔍 Reading release notes for version: $VERSION"

# Try to get release notes from GitHub Release
if command -v gh &> /dev/null; then
    if gh release view "$VERSION" > /dev/null 2>&1; then
        echo "✅ GitHub Release $VERSION found"
        RELEASE_NOTES=$(gh release view "$VERSION" --json body -q .body)
        echo "✅ Release notes extracted from GitHub Release"
    else
        echo "⚠️ GitHub Release $VERSION not found, using fallback notes"
        RELEASE_NOTES="• Bug fixes and performance improvements
• Enhanced user experience
• Updated for latest iOS compatibility"
    fi
else
    echo "⚠️ GitHub CLI not available, using fallback notes"
    RELEASE_NOTES="• Bug fixes and performance improvements
• Enhanced user experience
• Updated for latest iOS compatibility"
fi

# Display the notes
echo ""
echo "📝 Release Notes (for App Store):"
echo "=================================="
echo "$RELEASE_NOTES"

# Make notes available for Bitrise App Store submission
if command -v envman &> /dev/null; then
    envman add --key RELEASE_NOTES --value "$RELEASE_NOTES"
    echo ""
    echo "✅ Release notes exported to RELEASE_NOTES environment variable"
fi

# Release notes are ready for App Store submission via environment variable

echo ""
echo "🏷️ Source: GitHub Release $VERSION (or fallback if not found)"
