#!/bin/bash

# Convos iOS Release Tag Creator
# This script creates a release tag with proper version bumping

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if we're on dev branch
check_dev_branch() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$current_branch" != "dev" ]; then
        print_error "You must be on the 'dev' branch to create a release tag"
        print_status "Current branch: $current_branch"
        print_status "Please checkout dev branch first: git checkout dev"
        exit 1
    fi
    print_success "On dev branch ✓"
}

# Function to check if working directory is clean
check_clean_working_dir() {
    if [ -n "$(git status --porcelain)" ]; then
        print_warning "Working directory has uncommitted changes:"
        git status --short
        echo ""
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            print_error "Release cancelled"
            exit 1
        fi
    else
        print_success "Working directory is clean ✓"
    fi
}

# Function to get current version
get_current_version() {
    local current_version
    if [ -f "./Scripts/get-version.sh" ]; then
        current_version=$(./Scripts/get-version.sh 2>/dev/null || echo "unknown")
    else
        print_warning "get-version.sh not found, cannot determine current version"
        current_version="unknown"
    fi
    echo "$current_version"
}

# Function to update version in Xcode project
update_xcode_version() {
    local new_version="$1"
    local project_file="Convos.xcodeproj/project.pbxproj"
    local temp_file=""

    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would update version in Xcode project to $new_version..."
        print_success "DRY RUN: Version update simulation completed ✓"
        return 0
    fi

    print_status "Updating version in Xcode project to $new_version..."

    # Check if project file exists
    if [ ! -f "$project_file" ]; then
        print_error "Xcode project file not found: $project_file"
        exit 1
    fi

    # Create temporary file for atomic update
    temp_file=$(mktemp -p "$(dirname "$project_file")" "$(basename "$project_file").tmp.XXXXXXXXXX" 2>/dev/null) || \
              temp_file=$(mktemp "${project_file}.tmp.XXXXXXXXXX")
    if [ ! -f "$temp_file" ]; then
        print_error "Failed to create temporary file"
        exit 1
    fi

    # Copy original to temp file
    cp "$project_file" "$temp_file"

    # Update MARKETING_VERSION using portable sed
    local SED
    if command -v gsed >/dev/null 2>&1; then
        SED=gsed
    else
        SED=sed
    fi

    # Use appropriate in-place flag based on sed version
    if "$SED" --version >/dev/null 2>&1; then
        # GNU sed (Linux)
        if "$SED" -i "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;/MARKETING_VERSION = $new_version;/g" "$temp_file"; then
            print_success "Updated MARKETING_VERSION to $new_version ✓"
        else
            print_error "Failed to update MARKETING_VERSION"
            rm -f "$temp_file"
            exit 1
        fi
    else
        # BSD sed (macOS)
        if "$SED" -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;/MARKETING_VERSION = $new_version;/g" "$temp_file"; then
            print_success "Updated MARKETING_VERSION to $new_version ✓"
        else
            print_error "Failed to update MARKETING_VERSION"
            rm -f "$temp_file"
            exit 1
        fi
    fi

    # Verify the update in temp file
    local updated_count=$(grep -c "MARKETING_VERSION = $new_version;" "$temp_file" || echo "0")
    if [ "$updated_count" -gt 0 ]; then
        print_success "Verified $updated_count MARKETING_VERSION entries updated ✓"

        # Atomic move of temp file to original
        if mv "$temp_file" "$project_file"; then
            print_success "Version update completed successfully ✓"
        else
            print_error "Failed to apply version update"
            rm -f "$temp_file"
            exit 1
        fi
    else
        print_error "Version update verification failed"
        rm -f "$temp_file"
        exit 1
    fi
}

# Function to commit version update
commit_version_update() {
    local new_version="$1"

    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would commit version update to $new_version..."
        print_success "DRY RUN: Commit simulation completed ✓"
        return 0
    fi

    print_status "Committing version update to $new_version..."

    # Add the project file
    git add Convos.xcodeproj/project.pbxproj

    # Check if there are changes to commit
    if [ -z "$(git diff --cached)" ]; then
        print_warning "No changes to commit (version might already be $new_version)"
        return 0
    fi

    # Commit the changes
    if git commit -m "chore: bump version to $new_version"; then
        print_success "Version update committed ✓"
    else
        print_error "Failed to commit version update"
        exit 1
    fi
}

# Function to create tag and push atomically
create_tag_and_push_atomic() {
    local new_version="$1"

    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN: Would create tag $new_version..."
        print_status "DRY RUN: Would push dev branch and tag atomically to origin..."
        print_success "DRY RUN: Atomic push simulation completed ✓"
        return 0
    fi

    print_status "Creating tag $new_version..."

    # Create lightweight tag (GitHub Actions will create a release with notes)
    if git tag "$new_version"; then
        print_success "Tag $new_version created locally ✓"
    else
        print_error "Failed to create tag $new_version"
        exit 1
    fi

    print_status "Pushing dev branch and tag atomically to origin..."

    # Push both the branch and tag atomically in one operation
    if git push --atomic origin dev "$new_version"; then
        print_success "Dev branch and tag $new_version pushed atomically ✓"
    else
        print_error "Failed to push dev branch and tag atomically"
        # Clean up the local tag if push failed
        git tag -d "$new_version" 2>/dev/null
        exit 1
    fi
}

# Parse command line arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run]"
            echo "  --dry-run    Test the release workflow without making changes"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    if [ "$DRY_RUN" = true ]; then
        echo "📦 Convos iOS Release Tag Creator (DRY RUN MODE)"
        echo "================================================"
        echo ""
        print_warning "DRY RUN MODE: No actual changes will be made!"
        echo ""
    else
        echo "📦 Convos iOS Release Tag Creator"
        echo "=================================="
        echo ""
    fi

    # Check prerequisites
    check_dev_branch
    check_clean_working_dir

    # Get current version
    local current_version=$(get_current_version)
    echo ""
    print_status "Current version: $current_version"
    echo ""

    # Get new version from user
    read -p "Enter new version (e.g., 1.0.1 or 1.0.1-dev.123): " NEW_VERSION

    # Allow prerelease suffixes in the tag, but MARKETING_VERSION must be X.Y.X
    if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]]; then
        print_error "Invalid version format. Use semantic versioning (e.g., 1.0.1 or 1.0.1-dev.123)"
        exit 1
    fi

    # Compute base version for MARKETING_VERSION (strip anything after first '-')
    BASE_VERSION="$NEW_VERSION"
    if [[ "$BASE_VERSION" == *-* ]]; then
        BASE_VERSION="${BASE_VERSION%%-*}"
    fi

    # Enforce monotonic bump when current version is known (compare base versions)
    if [ "$current_version" != "unknown" ]; then
        # Simple version comparison using IFS
        IFS='.' read -r curr_major curr_minor curr_patch <<< "$current_version"
        IFS='.' read -r new_major new_minor new_patch <<< "$BASE_VERSION"

        if [ "$new_major" -lt "$curr_major" ] || \
           ([ "$new_major" -eq "$curr_major" ] && [ "$new_minor" -lt "$curr_minor" ]) || \
           ([ "$new_major" -eq "$curr_major" ] && [ "$new_minor" -eq "$curr_minor" ] && [ "$new_patch" -le "$curr_patch" ]); then
            print_error "New version ($BASE_VERSION) must be greater than current ($current_version)"
            exit 1
        fi
        print_success "Version bump validation passed ✓"
    fi

    # Confirm action
    echo ""
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - This will simulate:"
        echo "  1. Update MARKETING_VERSION in Xcode project to $BASE_VERSION"
        echo "  2. Commit the change to dev branch"
        echo "  3. Create tag $NEW_VERSION (may include prerelease suffix)"
        echo "  4. Push both tag and dev branch to origin"
        echo "  5. Trigger GitHub Actions to create release"
        echo ""
        print_status "No actual changes will be made!"
        echo ""
    else
        print_warning "This will:"
        echo "  1. Update MARKETING_VERSION in Xcode project to $BASE_VERSION"
        echo "  2. Commit the change to dev branch"
        echo "  3. Create tag $NEW_VERSION (may include prerelease suffix)"
        echo "  4. Push both tag and dev branch to origin"
        echo "  5. Trigger GitHub Actions to create release"
        echo ""
    fi

    read -p "Continue? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_error "Release cancelled"
        exit 1
    fi

    echo ""

    # Execute the release workflow
    update_xcode_version "$BASE_VERSION"
    commit_version_update "$BASE_VERSION"
    create_tag_and_push_atomic "$NEW_VERSION"

    echo ""
    if [ "$DRY_RUN" = true ]; then
        print_success "🔍 DRY RUN COMPLETED: Release workflow simulation finished!"
        echo ""
        print_status "What would happen next in a real run:"
        echo "  • GitHub Actions would automatically trigger on the tag"
        echo "  • A release PR would be created from dev → main"
        echo "  • Review the PR and merge when ready"
        echo "  • Bitrise would build and deploy to TestFlight"
        echo ""
        print_status "To perform the actual release, run: ./Scripts/create-release-tag.sh"
    else
        print_success "🎉 Release tag $NEW_VERSION created successfully!"
        echo ""
        print_status "What happens next:"
        echo "  • GitHub Actions will automatically trigger on the tag"
        echo "  • A release PR will be created from dev → main"
        echo "  • Review the PR and merge when ready"
        echo "  • Bitrise will build and deploy to TestFlight"
        echo ""
        print_status "Check the Actions tab in GitHub for progress"
    fi
}

# Run main function
main "$@"
