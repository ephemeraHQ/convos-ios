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
fi

  # Skip fingerprint validation for plugins and macros in Xcode (like SwiftLintBuildToolPlugin)
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

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

# Check and install GitHub CLI (skip installing in CI)
if [ ! "${CI}" = true ]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "Installing GitHub CLI..."
        if ! brew install gh; then
            echo "❌ Failed to install GitHub CLI. Please try installing manually:"
            echo "  brew install gh"
            exit 1
        fi
    fi
    # Verify gh is working
    if ! gh --version >/dev/null 2>&1; then
        echo "⚠️ gh installed but not working properly"
        echo "Try reinstalling: brew uninstall gh && brew install gh"
    else
        echo "✅ GitHub CLI is working"
        # Check authentication status
        if ! gh auth status >/dev/null 2>&1; then
            echo "ℹ️ GitHub CLI is not authenticated"
            echo "Run: gh auth login (to enable release automation)"
            echo "Or set GITHUB_TOKEN environment variable"
        else
            echo "✅ GitHub CLI is authenticated"
        fi
    fi
else
    echo "ℹ️ CI environment detected - GitHub CLI should be pre-installed in CI image"
fi

# Check Ruby version (require Ruby 3.3.3)
RUBY_VERSION=$(ruby -v | awk '{print $2}' | cut -d'p' -f1)
if [ "$RUBY_VERSION" != "3.3.3" ]; then
    echo "❌ Ruby version $RUBY_VERSION is not compatible."
    echo "This project requires Ruby 3.3.3"
    echo "Please install the correct version using:"
    echo "  - rbenv: rbenv install 3.3.3 && rbenv global 3.3.3"
    echo "  - rvm: rvm install 3.3.3 && rvm use 3.3.3"
    echo "  - Homebrew: brew install ruby@3.3 && brew link ruby@3.3"
    exit 1
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
