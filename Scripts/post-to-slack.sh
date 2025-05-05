#!/usr/bin/env bash

# Exit on any error
set -e

# Load environment variables
source ./Scripts/load-env.sh

# Check if SLACK_URL_WITH_KEY is set
if [ -z "$SLACK_URL_WITH_KEY" ]; then
    echo "❌ SLACK_URL_WITH_KEY environment variable is not set"
    exit 1
fi

# Parse command line arguments
for arg in "$@"; do
    case "$arg" in
        old=*)
            OLD_SHA="${arg#old=}"
            ;;
        new=*)
            NEW_SHA="${arg#new=}"
            ;;
        chosen_env=*)
            CHOSEN_ENV="${arg#chosen_env=}"
            ;;
    esac
done

# Function to get version display from SHA
get_version_display() {
    local sha=$1
    # Try to get the closest tag
    local describe_output=$(git describe --tags "$sha" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Extract the version number from the describe output
        # This handles both exact matches and commits after a tag
        local version=$(echo "$describe_output" | sed -E 's/-[0-9]+-g[0-9a-f]+$//')
        IFS='.' read -r MAJOR MINOR PATCH BUILD <<< "$version"
        echo "$MAJOR.$MINOR.$PATCH Build $BUILD"
    else
        # If no tag found, use the current version from Xcode project
        FULL_VERSION=$(./Scripts/get-version.sh)
        if [ -z "$FULL_VERSION" ]; then
            echo "❌ Could not determine current version from Xcode project"
            exit 1
        fi
        IFS='.' read -r MAJOR MINOR PATCH BUILD <<< "$FULL_VERSION"
        echo "$MAJOR.$MINOR.$PATCH Build $BUILD"
    fi
}

# If old/new SHAs not provided, use current version and previous version
if [ -z "$OLD_SHA" ] || [ -z "$NEW_SHA" ]; then
    # Get current version from Xcode project
    FULL_VERSION=$(./Scripts/get-version.sh)
    if [ -z "$FULL_VERSION" ]; then
        echo "❌ Could not determine current version from Xcode project"
        exit 1
    fi

    # Split version into components
    IFS='.' read -r MAJOR MINOR PATCH BUILD <<< "$FULL_VERSION"
    
    # Calculate previous version
    PREV_BUILD=$((BUILD - 1))
    OLD_SHA="$MAJOR.$MINOR.$PATCH.$PREV_BUILD"
    NEW_SHA="$FULL_VERSION"
fi

# Set default environment if not provided
CHOSEN_ENV=${CHOSEN_ENV:-"production"}
if [[ "$CHOSEN_ENV" =~ "production" || "$CHOSEN_ENV" =~ "prod" ]]; then
    ENV_DISPLAY="Production"
elif [[ "$CHOSEN_ENV" =~ "development" || "$CHOSEN_ENV" =~ "dev" ]] || "$CHOSEN_ENV" =~ "preview" ]]; then
    ENV_DISPLAY="Development (Preview)"
else
    ENV_DISPLAY="Production (default)"
fi

# Get version display for the new SHA
VERSION_DISPLAY=$(get_version_display "$NEW_SHA")

# Get changelog between versions/SHAs
CHANGELOG=$(git log --pretty="• %s" "$OLD_SHA".."$NEW_SHA")

# Construct Slack message
MESSAGE="🤖 <!channel> New TestFlight :rocket: :airplane_departure: $VERSION_DISPLAY.\n\nBuilt against: $ENV_DISPLAY. \n\nContains:\n\n$CHANGELOG"

# Escape the message for JSON
ESCAPED_MESSAGE=$(printf '%s' "$MESSAGE" | sed 's/"/\\"/g')

curl -X POST $SLACK_URL_WITHOUT_KEY \
  -H "Authorization: Bearer $SLACK_OAUTH_KEY" \
  -H 'Content-type: application/json' \
  --data "{\"channel\":\"$SLACK_CHANNEL_ID\",\"text\":\"$ESCAPED_MESSAGE\"}"
  
echo "✅ Posted release notification to Slack" 