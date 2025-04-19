#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# this script is used to increment the build number of the Xcode project
# Note: you can skip this script and just update the build number manually in Xcode

# check git status to ensure clean working tree
# this ensures that the commit contains the build number bump and nothing else.
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Git working tree is not clean. Please commit or stash your changes first."
  exit 1
fi

# Get the current build numbers before making changes
OLD_BUILD_NUMBER=$(./Scripts/get-build.sh | grep "Release:" | awk '{print $2}')

# Call sync-build.sh to increment the build number
./Scripts/sync-build.sh

# Get the new build number
NEW_BUILD_NUMBER=$(./Scripts/get-build.sh | grep "Release:" | awk '{print $2}')

# - ask dev if they want to commit the build number bump
# - set it manually for now. we don't need to ask the dev.
# read -p "Do you want to commit the build number bump? (y/n): " SHOULD_COMMIT_BUILD_BUMP
# if [[ "$SHOULD_COMMIT_BUILD_BUMP" != "y" && "$SHOULD_COMMIT_BUILD_BUMP" != "Y" ]]; then
#   echo "❗️ Skipping commit of build number bump."
#   exit 0
# fi

# Get the current build numbers from the project
echo "Current build numbers:"
./Scripts/get-build.sh

# commit the build number bump
git add Convos.xcodeproj
git commit -m "Bump build from $OLD_BUILD_NUMBER to $NEW_BUILD_NUMBER"

# ask dev if they want to push the commit
# - set it manually for now. we don't need to ask the dev.
# read -p "Do you want to push the commit? (y/n): " SHOULD_PUSH_COMMIT
# if [[ "$SHOULD_PUSH_COMMIT" != "y" && "$SHOULD_PUSH_COMMIT" != "Y" ]]; then
#   echo "❗️ Skipping push of commit."
#   exit 0
# fi

# Get the current version from the project
CURRENT_VERSION=$(./Scripts/get-version.sh)

# Create tag with full version (Major.Minor.Patch.Build)
FULL_VERSION="${CURRENT_VERSION}.${NEW_BUILD_NUMBER}"
git tag -a "$FULL_VERSION" -m "Build $NEW_BUILD_NUMBER"

echo "🏁 Created commit and tag $FULL_VERSION for build number bump from $OLD_BUILD_NUMBER to $NEW_BUILD_NUMBER" 