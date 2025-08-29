# GitHub Actions Workflows

This directory contains GitHub Actions workflows that automate the release process for the Convos iOS app.

## Workflows

### 1. Create Release PR (`create-release-pr.yml`)

**Manual trigger** - Run this workflow when you're ready to create a release PR.

**Features:**
- Interactive version bumping (patch/minor/major)
- AI-powered release notes generation using Anthropic Claude
- Automatic PR creation from `dev` to `main`
- Version update in Xcode project files

**Usage:**
1. Go to Actions tab in GitHub
2. Select "Create Release PR" workflow
3. Click "Run workflow"
4. Choose release type and options
5. Review generated PR and merge

### 2. Auto Create Release PR (`auto-release-pr.yml`)

**Automatic trigger** - Runs when you push a semantic version tag.

**Features:**
- Triggers on `git tag 1.0.1 && git push origin 1.0.1`
- Automatic version extraction from tag
- AI-powered release notes generation using Claude
- Updates version in dev branch and creates PR from dev to main

**Usage:**
```bash
# From your local machine (recommended)
make tag-release

# OR manually:
git tag 1.0.1
git push origin 1.0.1
```

## Prerequisites

### Required Secrets

Add these secrets to your GitHub repository:

1. **`ANTHROPIC_API_KEY`** - Your Anthropic API key for generating release notes with Claude
2. **`GITHUB_TOKEN`** - Automatically provided by GitHub Actions

### Setup

1. **Install GitHub CLI** (required for PR creation):
   ```bash
   # On macOS
   brew install gh

   # On Ubuntu
   curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
   sudo apt update
   sudo apt install gh
   ```

2. **Authenticate GitHub CLI**:
   ```bash
   gh auth login
   ```

## Release Process

### Option 1: Manual Workflow (Recommended for major releases)

1. **Prepare Release**:
   - Ensure all features are merged to `dev`
   - Test thoroughly on TestFlight
   - Decide on version bump (patch/minor/major)

2. **Run Workflow**:
   - Go to Actions → Create Release PR
   - Choose release type and options
   - Review generated PR

3. **Review and Merge**:
   - Review AI-generated release notes
   - Update version in Xcode if needed
   - Merge PR to `main`

### Option 2: Tag-Based Automation (Great for regular releases)

1. **Create Release Tag**:
   ```bash
   make tag-release  # This will:
   # - Ensure you're on dev branch
   # - Update version in Xcode project
   # - Commit to dev branch
   # - Create and push tag
   # - Push dev branch

   # OR manually:
   git tag 1.0.1
   git push origin 1.0.1
   ```

2. **Automatic Process**:
   - GitHub Actions verifies version in dev branch matches tag
   - Generates AI release notes
   - Creates PR from `dev` to `main` (ready for rebase merge)

3. **Review and Merge**:
   - Review the auto-generated PR
   - Merge to `main` when ready (rebase merge, linear history)

## Release Notes

The workflows generate two types of release notes:

### 👥 Internal Notes
- **Detailed technical changes**
- **Testing notes**
- **Deployment considerations**
- **Team-focused language**

### 👤 Customer Notes
- **User-friendly feature descriptions**
- **Simple bug fix explanations**
- **Performance improvements**
- **Warm, encouraging tone**

## Integration with Bitrise

After merging the release PR to `main`:

1. **Bitrise automatically triggers** production build
2. **Build number** is injected from `BITRISE_BUILD_NUMBER`
3. **Version** comes from Xcode project (updated by workflow)
4. **TestFlight deployment** happens automatically
5. **App Store submission** can be done manually or automated

## Troubleshooting

### Common Issues

1. **GitHub CLI not found**:
   - Install GitHub CLI as shown in setup
   - Ensure it's available in PATH

2. **Anthropic API errors**:
   - Check `ANTHROPIC_API_KEY` secret is set
   - Verify API key has sufficient credits
   - Check API rate limits

3. **Version mismatch**:
   - Ensure Xcode project has consistent `MARKETING_VERSION`
   - Run `make version` to check current version
   - Use `make tag-release` for proper versioning

### Debugging

- Check Actions tab for detailed logs
- Look for specific error messages in workflow steps
- Verify repository permissions and secrets

## Best Practices

1. **Use semantic versioning** (1.0.0, 1.0.1, 1.1.0, 2.0.0)
2. **Test on TestFlight** before creating release PR
3. **Review AI-generated notes** for accuracy
4. **Keep release notes user-friendly** for customer-facing content
5. **Use descriptive commit messages** for better release notes

## Support

For issues with these workflows:
1. Check the Actions tab logs
2. Verify all prerequisites are met
3. Ensure secrets are properly configured
4. Check GitHub Actions documentation
