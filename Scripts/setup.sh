#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# setup developer environment

# Check if Ruby is installed
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby is not installed. Please install Ruby first."
    echo "You can install Ruby using:"
    echo "  - Homebrew: brew install ruby@3.3"
    echo "  - rbenv: https://github.com/rbenv/rbenv"
    echo "  - rvm: https://rvm.io/"
    exit 1
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
if ! bundle install; then
    echo "❌ Failed to install dependencies. Please check the Gemfile and try again."
    exit 1
fi

echo "✅ All dependencies are properly installed" 