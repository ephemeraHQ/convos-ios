#!/usr/bin/env bash

# Exit on error
set -e

# Source .env file if it exists (for local development)
if [ -f .env ]; then
  source .env
fi

# Check if sentry-cli is installed
if ! command -v sentry-cli &>/dev/null; then
  echo "Error: sentry-cli is not installed. Please install it first."
  echo "You can install it using: brew install getsentry/tools/sentry-cli"
  exit 1
fi

# Check if auth token exists in CI environment
if [ -z "$SENTRY_UPLOAD_SYMBOLS_AUTH_TOKEN" ]; then
  echo "Error: SENTRY_UPLOAD_SYMBOLS_AUTH_TOKEN environment variable is not set"
  echo "Please ensure this variable is set in your Bitrise workflow or .env file"
  exit 1
fi

# Check if org and project are set
if [ -z "$SENTRY_ORG" ]; then
  echo "Error: SENTRY_ORG environment variable is not set"
  echo "Please ensure this variable is set in your Bitrise workflow or .env file"
  exit 1
fi

if [ -z "$SENTRY_PROJECT" ]; then
  echo "Error: SENTRY_PROJECT environment variable is not set"
  echo "Please ensure this variable is set in your Bitrise workflow or .env file"
  exit 1
fi

# Determine dSYM directory path (Bitrise takes precedence)
if [ -n "$BITRISE_DSYM_DIR_PATH" ]; then
  DSYM_DIR_PATH="$BITRISE_DSYM_DIR_PATH"
  echo "Using Bitrise dSYM directory path"
elif [ -n "$DSYM_DIR_PATH" ]; then
  echo "Using local dSYM directory path from .env"
else
  echo "Error: No dSYM directory path found"
  echo "Please set either BITRISE_DSYM_DIR_PATH (in Bitrise) or DSYM_DIR_PATH (in .env)"
  exit 1
fi

# Debug information
echo "dSYM directory path: $DSYM_DIR_PATH"
echo "Contents of dSYM directory:"
ls -la "$DSYM_DIR_PATH" || true

# Verify dSYM files exist
if ! ls "$DSYM_DIR_PATH"/*.dSYM 1>/dev/null 2>&1; then
  echo "Error: No dSYM files found at $DSYM_DIR_PATH"
  echo "Please verify that dSYM generation is enabled in your Xcode build settings"
  exit 1
fi

# Upload dSYM files to Sentry
sentry-cli debug-files upload \
  --auth-token "$SENTRY_UPLOAD_SYMBOLS_AUTH_TOKEN" \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  "$DSYM_DIR_PATH"/*.dSYM
