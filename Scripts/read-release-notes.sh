#!/bin/bash

set -e
set -o pipefail

# Get the version from Xcode project
VERSION=$(grep -o 'MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;' Convos.xcodeproj/project.pbxproj | head -1 | sed 's/MARKETING_VERSION = \([0-9]*\.[0-9]*\.[0-9]*\);/\1/' || echo "")

# Check if VERSION extraction failed and provide fallback
if [ -z "$VERSION" ]; then
    VERSION="0.0.0"
    echo "⚠️ Failed to extract version from Xcode project, using fallback: $VERSION"
else
    echo "🔍 Reading release notes for version: $VERSION"
fi

FALLBACK_NOTES="• Bug fixes and performance improvements
• Enhanced user experience
• Updated for latest iOS compatibility"

# Try to get release notes from GitHub Release
if command -v gh &> /dev/null; then
    # Get repository information
    if [ -n "$GITHUB_REPOSITORY" ]; then
        # Use GITHUB_REPOSITORY from Bitrise environment
        REPO="$GITHUB_REPOSITORY"
        echo "🔍 Using repository from GITHUB_REPOSITORY: $REPO"
    elif [ -d .git ]; then
        # Try to get repo from git remote
        REPO=$(git remote get-url origin 2>/dev/null | sed 's/.*github\.com[:/]\([^/]*\/[^/]*\)\.git/\1/' | sed 's/.*github\.com[:/]\([^/]*\/[^/]*\)$/\1/')
        if [ -n "$REPO" ]; then
            echo "🔍 Using repository from git remote: $REPO"
        fi
    fi

    if [ -n "$REPO" ]; then
        echo "🔍 Checking GitHub Release $VERSION in repository: $REPO"
        if gh release view "$VERSION" --repo "$REPO" > /dev/null 2>&1; then
            echo "✅ GitHub Release $VERSION found in $REPO"
            RELEASE_NOTES=$(gh release view "$VERSION" --repo "$REPO" --json body -q .body)
            echo "✅ Release notes extracted from GitHub Release"
        else
            echo "⚠️ GitHub Release $VERSION not found in $REPO, using fallback notes"
            RELEASE_NOTES="$FALLBACK_NOTES"
        fi
    else
        echo "⚠️ Could not determine repository, using fallback notes"
        RELEASE_NOTES="$FALLBACK_NOTES"
    fi
else
    echo "⚠️ GitHub CLI not available, using fallback notes"
    RELEASE_NOTES="$FALLBACK_NOTES"
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
