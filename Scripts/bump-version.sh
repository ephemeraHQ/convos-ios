#!/usr/bin/env bash

# this script is used to bump the version of the Xcode project
# Note: you can skip this script and just update the version manually in Xcode

# this script can be called from the command line with one argument
# (argument is optional from terminal but is required and will be interactively prompted for if not provided):
# 1. the version to bump to (format: Major.Minor.Patch)

# check git status to ensure clean working tree
# this ensures that the commit contains the version bump and nothing else.
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Git working tree is not clean. Please commit or stash your changes first."
  exit 1
fi

VERSION_INPUT="$1"

# Helper functions:

# helper to validate semantic version
validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Validation requirements:

# prompt for version if not provided or invalid
if ! validate_version "$VERSION_INPUT"; then
  while true; do
    read -p "Enter version (e.g. 1.15.0): " VERSION_INPUT
    if validate_version "$VERSION_INPUT"; then
      break
    else
      echo "❌ Invalid version format. Must be semantic version: major.minor.patch"
    fi
  done
fi

# input is validated and determined its safe to use $VERSION_INPUT

# update Xcode project version
if validate_version "$VERSION_INPUT"; then
  # Append .1 as the build number
  FULL_VERSION="${VERSION_INPUT}.1"
  
  # Call sync-versions.sh with the new version
  ./Scripts/sync-versions.sh "$VERSION_INPUT"

  # check that tag for this version does not already exist
  if git rev-parse "$FULL_VERSION" >/dev/null 2>&1; then
    echo "❌ Tag $FULL_VERSION already exists. Please delete the tag and try again."
    exit 1
  fi

  # ask dev if they want to commit the version bump
  read -p "Do you want to commit the version bump? (y/n): " SHOULD_COMMIT_VERSION_BUMP
  if [[ "$SHOULD_COMMIT_VERSION_BUMP" != "y" && "$SHOULD_COMMIT_VERSION_BUMP" != "Y" ]]; then
    echo "❗️ Skipping commit of version bump."
    exit 0
  fi

  # commit the version bump
  git add Convos.xcodeproj
  git commit -m "Bump version to $VERSION_INPUT Build 1"
  # annotate with a git tag for the version
  git tag -a "$FULL_VERSION" -m "(Automated) Bump version to $VERSION_INPUT Build 1"

  # ask dev if they want to push the commit and tag
  read -p "Do you want to push the commit and tag? (y/n): " SHOULD_PUSH_COMMIT
  if [[ "$SHOULD_PUSH_COMMIT" != "y" && "$SHOULD_PUSH_COMMIT" != "Y" ]]; then
    echo "❗️ Skipping push of commit and tag."
    exit 0
  fi

  # push the commit and tag to the remote
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git push -u origin "$current_branch"
  git push origin "$FULL_VERSION"

  echo "🏁 Created commit and tag for version $VERSION_INPUT Build 1"
fi