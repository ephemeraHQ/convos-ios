#!/usr/bin/env bash

# Exit on any error and ensure pipeline failures are caught
set -e
set -o pipefail

# This script creates environment-specific schemes and configurations
# Usage: ./set-environment.sh [local|dev|prod]
# This works by modifying build configurations and schemes

# Available environments
VALID_ENVS=("local" "dev" "prod")

# Function to display usage
show_usage() {
    echo "🌍 Environment Configuration for Convos"
    echo ""
    echo "Usage: $0 [environment] [action]"
    echo ""
    echo "Environments:"
    echo "  local  - Local development with XMTP local network"
    echo "  dev    - Development/TestFlight with real XMTP dev network"
    echo "  prod   - Production with real XMTP production network"
    echo ""
    echo "Actions:"
    echo "  setup    - Set up build configurations and schemes for environment switching"
    echo "  switch   - Switch to specific environment (default action)"
    echo ""
    echo "Examples:"
    echo "  $0 setup              # Set up all environment configurations"
    echo "  $0 local              # Switch to local (same as: $0 local switch)"
    echo "  $0 dev switch         # Switch to dev environment"
    echo ""
    echo "💡 After setup, you can switch environments using Xcode schemes:"
    echo "   • Select 'Convos Local', 'Convos Dev', or 'Convos Prod' from scheme dropdown"
}

# Function to validate environment
validate_env() {
    local env=$1
    for valid_env in "${VALID_ENVS[@]}"; do
        if [ "$env" = "$valid_env" ]; then
            return 0
        fi
    done
    return 1
}

# Function to set up environment configurations
setup_environments() {
    echo "🛠️  Setting up environment configurations..."
    echo ""

    # Check if we have the required config files
    for env in "${VALID_ENVS[@]}"; do
        config_file="Convos/Config/config.${env}.json"
        xcconfig_file="Convos/Config/$(echo ${env:0:1} | tr '[:lower:]' '[:upper:]')$(echo ${env:1}).xcconfig"

        if [ ! -f "$config_file" ]; then
            echo "❌ Missing config file: $config_file"
            exit 1
        fi

        if [ ! -f "$xcconfig_file" ]; then
            echo "❌ Missing xcconfig file: $xcconfig_file"
            exit 1
        fi
    done

    echo "✅ All required configuration files found"
    echo ""
    echo "📝 Manual setup required in Xcode:"
    echo ""
    echo "1. Open Convos.xcodeproj"
    echo ""
    echo "2. Set up Build Configurations:"
    echo "   • Project → Info → Configurations"
    echo "   • Duplicate 'Debug' → Rename to 'Dev'"
    echo "   • Final configurations: Debug, Dev, Release"
    echo ""
    echo "3. Assign Configuration Files:"
    echo "   For ALL targets (Convos, ConvosTests, ConvosAppClip, ConvosAppClipTests, NotificationService):"
    echo "   • Debug → Convos/Config/Local.xcconfig"
    echo "   • Dev → Convos/Config/Dev.xcconfig"
    echo "   • Release → Convos/Config/Prod.xcconfig"
    echo ""
    echo "4. Update Bundle Identifiers (in Build Settings):"
    echo "   • Convos → Product Bundle Identifier → \$(CONVOS_BUNDLE_ID)"
    echo "   • ConvosTests → Product Bundle Identifier → \$(CONVOS_TESTS_BUNDLE_ID)"
    echo "   • ConvosAppClip → Product Bundle Identifier → \$(CONVOS_APP_CLIP_BUNDLE_ID)"
    echo "   • ConvosAppClipTests → Product Bundle Identifier → \$(CONVOS_APP_CLIP_TESTS_BUNDLE_ID)"
    echo "   • NotificationService → Product Bundle Identifier → \$(NOTIFICATION_SERVICE_BUNDLE_ID)"
    echo ""
    echo "5. Create Environment Schemes:"
    echo "   • Product → Scheme → New Scheme"
    echo "   • 'Convos Local' → Use Debug configuration"
    echo "   • 'Convos Dev' → Use Dev configuration"
    echo "   • 'Convos Prod' → Use Release configuration"
    echo ""
    echo "🚀 After setup, switch environments by selecting the appropriate scheme!"
}

# Function to switch environment via scheme selection
switch_environment() {
    local env=$1

    if ! validate_env "$env"; then
        echo "❌ Invalid environment: $env"
        echo "Valid environments: ${VALID_ENVS[*]}"
        exit 1
    fi

    # Map environment to scheme name
    case "$env" in
        local) scheme="Convos Local" ;;
        dev) scheme="Convos Dev" ;;
        prod) scheme="Convos Prod" ;;
    esac

    echo "🔄 To switch to $env environment:"
    echo ""
    echo "In Xcode:"
    echo "1. Select '$scheme' from the scheme dropdown (top toolbar)"
    echo "2. Build and run (⌘+R)"
    echo ""
    echo "Or from command line:"
    case "$env" in
        local) config="Debug" ;;
        dev) config="Dev" ;;
        prod) config="Release" ;;
    esac
    echo "xcodebuild -scheme '$scheme' -configuration $config build"
    echo ""

    # Show what this environment includes
    config_file="Convos/Config/config.${env}.json"
    if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
        echo "📊 $env environment config:"
        jq -r 'to_entries[] | "  \(.key): \(.value)"' "$config_file"
    fi
}

# Main script logic
if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

case "$1" in
    setup)
        setup_environments
        ;;
    -h|--help|help)
        show_usage
        ;;
    local|dev|prod)
        if [ "$2" = "setup" ]; then
            setup_environments
        else
            switch_environment "$1"
        fi
        ;;
    *)
        echo "❌ Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
