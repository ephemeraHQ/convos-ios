#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# this script creates a release branch for the current version
# Usage: ./release.sh

# Check for required dependencies
echo "Checking dependencies..."
./Scripts/setup.sh
if [ $? -ne 0 ]; then
  exit 1
fi

# check git status to ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Git working tree is not clean. Please commit or stash your changes first."
  exit 1
fi

# Check that all targets have matching version numbers
echo "Checking version numbers across all targets..."
./Scripts/get-version.sh > /dev/null
if [ $? -ne 0 ]; then
  exit 1
fi

# Check that all targets have matching build numbers
echo "Checking build numbers across all targets..."
./Scripts/check-build-numbers.sh
if [ $? -ne 0 ]; then
  exit 1
fi

# Get current version from Xcode project
FULL_VERSION=$(./Scripts/get-version.sh)
if [ -z "$FULL_VERSION" ]; then
  echo "❌ Could not determine current version from Xcode project"
  exit 1
fi

# Extract major.minor version
VERSION=$(echo "$FULL_VERSION" | cut -d. -f1,2)

echo "Current version: $FULL_VERSION"
echo "Release branch version: $VERSION"

# check if release branch already exists
if git show-ref --verify "refs/heads/release/$VERSION"; then
  echo "❌ Release branch 'release/$VERSION' already exists."
  exit 1
fi

# check if release branch exists on remote
if git ls-remote --heads origin "release/$VERSION" | grep -q "release/$VERSION"; then
  echo "❌ Release branch 'release/$VERSION' already exists on remote."
  exit 1
fi

# create and switch to release branch
echo "Creating release branch 'release/$VERSION'..."
git checkout -b "release/$VERSION"

# push the release branch to origin
echo "Pushing release branch to origin..."
git push -u origin "release/$VERSION"

# switch back to main branch
git checkout main

echo "🏁 Created and pushed release branch 'release/$VERSION'" 