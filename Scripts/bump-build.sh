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

# Call sync-build.sh to increment the build number
./Scripts/sync-build.sh

# ask dev if they want to commit the build number bump
read -p "Do you want to commit the build number bump? (y/n): " SHOULD_COMMIT_BUILD_BUMP
if [[ "$SHOULD_COMMIT_BUILD_BUMP" != "y" && "$SHOULD_COMMIT_BUILD_BUMP" != "Y" ]]; then
  echo "❗️ Skipping commit of build number bump."
  exit 0
fi

# Get the current build numbers from the project
echo "Current build numbers:"
./Scripts/get-build.sh

# commit the build number bump
git add Convos/Convos.xcodeproj
git commit -m "Bump build numbers"

# ask dev if they want to push the commit
read -p "Do you want to push the commit? (y/n): " SHOULD_PUSH_COMMIT
if [[ "$SHOULD_PUSH_COMMIT" != "y" && "$SHOULD_PUSH_COMMIT" != "Y" ]]; then
  echo "❗️ Skipping push of commit."
  exit 0
fi

# push the commit to the remote
current_branch=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$current_branch"

echo "🏁 Created commit for build number bump" 