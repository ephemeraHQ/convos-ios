#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# style the output
function info {
  echo "[$(basename "${0}")] [INFO] ${1}"
}

# style the output
function die {
  echo "[$(basename "${0}")] [ERROR] ${1}"
  exit 1
}

# get the directory name of the script
DIRNAME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# setup developer environment

if [ ! "${CI}" = true ]; then
  # assumes you are in ./Scripts/ folder
  git_dir="${DIRNAME}/../.git"
  pre_commit_file="../../Scripts/hooks/pre-commit"
  pre_push_file="../../Scripts/hooks/pre-push"
  post_checkout_file="../../Scripts/hooks/post-checkout"
  post_merge_file="../../Scripts/hooks/post-merge"

  info "Installing Git hooks..."
  cd "${git_dir}"
  if [ ! -L hooks/pre-push ]; then
      ln -sf "${pre_push_file}" hooks/pre-push
  fi
  if [ ! -L hooks/pre-commit ]; then
      ln -sf "${pre_commit_file}" hooks/pre-commit
  fi
  if [ ! -L hooks/post-checkout ]; then
      ln -sf "${post_checkout_file}" hooks/post-checkout
  fi
  if [ ! -L hooks/post-merge ]; then
      ln -sf "${post_merge_file}" hooks/post-merge
  fi
  cd "${DIRNAME}"
fi

################################################################################
# Xcode                                                                        #
################################################################################

if [ ! "${CI}" = true ]; then
  info "Installing Xcode defaults..."
  defaults write com.apple.dt.Xcode DVTTextEditorTrimTrailingWhitespace -bool true
  defaults write com.apple.dt.Xcode DVTTextEditorTrimWhitespaceOnlyLines -bool true
  defaults write com.apple.dt.Xcode DVTTextPageGuideLocation -int 120
  defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool true

  # Skip fingerprint validation for plugins and macros in Xcode (like SwiftLintBuildToolPlugin)
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
else
  info "CI environment detected - setting Xcode defaults for CI..."
  # In CI, also skip plugin validation to avoid build failures
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
fi

################################################################################
# Setup Dependencies                                                           #
################################################################################

# Check if Ruby is installed
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby is not installed. Please install Ruby first."
    echo "You can install Ruby using:"
    echo "  - Homebrew: brew install ruby@3.3"
    echo "  - rbenv: https://github.com/rbenv/rbenv"
    echo "  - rvm: https://rvm.io/"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew is not installed. Please install Homebrew first."
    echo "You can install Homebrew using:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Check and install SwiftLint
if ! command -v swiftlint &> /dev/null; then
    echo "Installing SwiftLint..."
    if ! brew install swiftlint; then
        echo "❌ Failed to install SwiftLint. Please try installing manually:"
        echo "  brew install swiftlint"
        exit 1
    fi
fi

# Check and install SwiftFormat
if ! command -v swiftformat &> /dev/null; then
    echo "Installing SwiftFormat..."
    if ! brew install swiftformat; then
        echo "❌ Failed to install SwiftFormat. Please try installing manually:"
        echo "  brew install swiftformat"
        exit 1
    fi
fi

# Check Ruby version (require Ruby 3.3.0 or higher)
RUBY_VERSION=$(ruby -v | awk '{print $2}' | cut -d'p' -f1)
RUBY_MAJOR=$(echo "$RUBY_VERSION" | cut -d'.' -f1)
RUBY_MINOR=$(echo "$RUBY_VERSION" | cut -d'.' -f2)
RUBY_PATCH=$(echo "$RUBY_VERSION" | cut -d'.' -f3)

# Check if Ruby version is 3.3.0 or higher
if [ "$RUBY_MAJOR" -lt 3 ] || [ "$RUBY_MAJOR" -eq 3 -a "$RUBY_MINOR" -lt 3 ]; then
    echo "❌ Ruby version $RUBY_VERSION is not compatible."
    echo "This project requires Ruby 3.3.0 or higher"
    echo "Please install a compatible version using:"
    echo "  - rbenv: rbenv install 3.3.3 && rbenv global 3.3.3"
    echo "  - rvm: rvm install 3.3.3 && rvm use 3.3.3"
    echo "  - Homebrew: brew install ruby@3.3 && brew link ruby@3.3"
    exit 1
else
    echo "✅ Ruby version $RUBY_VERSION is compatible (3.3.0+ required)"
fi

# Check if Bundler is installed
if ! command -v bundle &> /dev/null; then
    echo "Installing Bundler..."
    if ! gem install bundler; then
        echo "❌ Failed to install Bundler. Please try installing manually:"
        echo "  gem install bundler"
        exit 1
    fi
fi

# Install dependencies from Gemfile
echo "Installing dependencies from Gemfile..."

# In CI, allow flexible Ruby version by regenerating Gemfile.lock if needed
if [ "${CI}" = true ]; then
    echo "CI environment detected - ensuring compatible Gemfile.lock"
    # Remove lockfile if Ruby version mismatch in CI
    if bundle check 2>/dev/null | grep -q "Your Ruby version is"; then
        echo "Ruby version mismatch in CI - regenerating Gemfile.lock"
        rm -f Gemfile.lock
    fi
fi

if ! bundle install; then
    echo "❌ Failed to install dependencies. Please check the Gemfile and try again."
    exit 1
fi

echo "✅ All dependencies are properly installed"
