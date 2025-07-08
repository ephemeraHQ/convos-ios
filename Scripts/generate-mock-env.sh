#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# style the output
function info {
  echo "[$(basename "${0}")] [INFO] ${1}"
}

function die {
  echo "[$(basename "${0}")] [ERROR] ${1}"
  exit 1
}

# This script generates a mock .env file for PR builds
# Usage: ./generate-mock-env.sh
#
# The script reads keys from .env.example and creates a .env file
# using MOCK_ prefixed Bitrise secrets (e.g., MOCK_FIREBASE_APP_CHECK_TOKEN)

info "🔑 Generating mock .env file for PR builds"

# Check if .env.example file exists
if [ ! -f ".env.example" ]; then
  die ".env.example file not found"
fi

# Remove existing .env file if it exists
if [ -f ".env" ]; then
  info "Removing existing .env file"
  rm .env
fi

# Read .env.example and generate .env with mock values
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  # Skip comments and empty lines
  [[ $key =~ ^#.*$ ]] && continue
  [[ -z $key ]] && continue

  # Remove any leading/trailing whitespace from key
  key=$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # Skip if key is empty after trimming
  [[ -z $key ]] && continue

  # Create the mock secret name with MOCK_ prefix
  mock_secret="MOCK_${key}"

  # Get the mock value from Bitrise environment variable
  mock_value="${!mock_secret}"

  # If the mock secret is not set, use a default mock value
  if [ -z "$mock_value" ]; then
    mock_value="mock_$(echo "$key" | tr '[:upper:]' '[:lower:]')"  # lowercase version of key
    info "Using default mock value for $key: $mock_value"
  else
    info "Using Bitrise secret $mock_secret for $key"
  fi

  # Write to .env file
  echo "$key=$mock_value" >> .env

done < .env.example

info "✅ Generated mock .env file with $(wc -l < .env) environment variables"
