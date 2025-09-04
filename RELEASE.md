# Release Process

This document describes the automated release process for the Convos iOS app.

## Quick Start

```bash
make tag-release
```

This command handles the entire release workflow automatically.

## Release Workflow

1. **Prepare Release**:
   - Ensure all features are merged to `dev` branch
   - Test thoroughly on TestFlight
   - Decide on version number (semantic versioning)

2. **Create Release Tag**:
   ```bash
   make tag-release
   ```
   
   This will:
   - Ensure you're on the `dev` branch
   - Update version in Xcode project
   - Commit the version change to `dev`
   - Create and push the tag atomically
   - Push the `dev` branch to origin

3. **Automatic GitHub Actions Process**:
   - Verifies version in `dev` branch matches the tag
   - Generates AI-powered release notes using Claude
   - Creates a GitHub Release with the generated notes
   - Creates a PR from `dev` to `main`

4. **Review and Deploy**:
   - Review the auto-generated PR and release notes
   - Merge PR to `main` using "Rebase and merge" (linear history)
   - Bitrise automatically builds and deploys to TestFlight

## Release Notes

The workflow generates customer-friendly release notes using AI:

- **Short, concise bullet points** (maximum 5)
- **User-focused benefits** (not technical details)
- **Warm, friendly language**
- **Each point under 15 words**
- **No technical jargon**

These notes are used for:
- GitHub Release descriptions
- App Store Connect submission (via Bitrise)
- TestFlight release notes

## Complete Release Pipeline

1. **Tag Creation** → Triggers GitHub Actions
2. **GitHub Release** → Created with AI-generated notes
3. **PR Merge to `main`** → Triggers Bitrise production build
4. **Bitrise Reads Release Notes** → From GitHub Release API
5. **App Store Connect** → Deploys with release notes to TestFlight
6. **TestFlight** → Ready for internal/external testing

## GitHub Actions Workflow

The automated workflow (`auto-release-pr.yml`) triggers on semantic version tags and:

- Triggers on semantic version tags (e.g., `1.0.1`)
- AI-powered release notes generation using Anthropic Claude
- Creates GitHub Release with generated notes
- Creates PR from `dev` to `main` for linear history
- Verifies version consistency between dev branch and tag
- Provides release notes to Bitrise for App Store Connect

## Prerequisites

### Required Secrets

Add these secrets to your GitHub repository:

1. **`ANTHROPIC_API_KEY`** - Your Anthropic API key for generating release notes with Claude
2. **`GITHUB_TOKEN`** - Automatically provided by GitHub Actions

### Setup

```bash
make setup
```

This will install all required dependencies and set up the development environment.

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

For issues with the release process:
1. Check the Actions tab logs
2. Verify all prerequisites are met
3. Ensure secrets are properly configured
4. Check GitHub Actions documentation