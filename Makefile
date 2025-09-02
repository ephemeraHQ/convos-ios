# Set default goal
.DEFAULT_GOAL := help

# Configure shell for safer execution
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: help
help: ## Print comprehensive help for all commands
	@echo "🔧 Convos iOS Development Commands"
	@echo "=================================="
	@echo ""
	@echo "🔑 Secrets Management:"
	@echo "   make secrets        - Generate Secrets.swift for CI/CD"
	@echo "   make secrets-local  - Generate Secrets.swift for local development"
	@echo "   make mock-env       - Generate mock environment for PR builds"
	@echo ""
	@echo "📱 Version Management:"
	@echo "   make version        - Show current version from Xcode project"
	@echo "   make dry-run-release - Test release workflow with confirmation"
	@echo "   make dry-run-release-quick - Quick test without confirmation"
	@echo "   make tag-release    - Create and push a release tag (triggers auto-PR with rebase merge)"
	@echo ""
	@echo "🔧 Setup & Maintenance:"
	@echo "   make setup          - Setup development environment"
	@echo "   make clean          - Clean all generated files and build artifacts"
	@echo "   make status         - Show project status"
	@echo ""
	@echo "🌐 Environment Configuration:"
	@echo "   • Local: org.convos.ios (local development, no CI)"
	@echo "   • Dev: org.convos.ios-preview (TestFlight internal, CI: dev branch)"
	@echo "   • Prod: org.convos.ios (App Store, CI: main branch)"
	@echo ""
	@echo "📋 Build Workflow:"
	@echo "   • Local: Version from Xcode, Build always 1"
	@echo "   • Dev: Version from Xcode, Build from BITRISE_BUILD_NUMBER"
	@echo "   • Prod: Version from Xcode, Build from BITRISE_BUILD_NUMBER"
	@echo ""
	@echo "🔄 Release Process:"
	@echo "   1. Feature branches → dev (merge on dev triggers a dev TestFlight build)"
	@echo "   2. Create release: git tag 1.0.1 && git push origin 1.0.1 (auto-creates PR)"
	@echo "   3. Review and merge PR: dev → main (rebase merge, linear history)"
	@echo "   4. Main → App Store (after review and approval)"

.PHONY: setup
setup: ## Setup dependencies and developer environment
	./Scripts/setup.sh

.PHONY: secrets
secrets: ## Generate Secrets.swift (auto-detects environment)
	@if [ -n "$$CI" ] || [ -n "$$BITRISE" ]; then echo "🔧 CI/CD environment detected, using secure secrets..."; ./Scripts/generate-secrets-secure.sh; else echo "🏠 Local environment detected, using local secrets..."; ./Scripts/generate-secrets-local.sh; fi

.PHONY: secrets-local
secrets-local: ## Generate Secrets.swift with auto-detected local IP
	./Scripts/generate-secrets-local.sh

.PHONY: ensure-secrets
ensure-secrets: ## Ensure minimal Secrets.swift exists
	./Scripts/generate-secrets-local.sh --ensure-only

.PHONY: mock-env
mock-env: ## Generate a mock .env file for PR builds
	./Scripts/generate-mock-env.sh

.PHONY: version
version: ## Get current version from Xcode project
	./Scripts/get-version.sh

.PHONY: clean
clean: ## Clean generated files
	rm -f Convos/Config/Secrets.swift
	rm -rf build/
	rm -rf DerivedData/
	rm -rf *.xcarchive
	rm -rf *.ipa

.PHONY: status
status: ## Show project status (version, secrets, git)
	@echo "📱 Project Status"
	@echo "=================="
	@echo "Version: $$(./Scripts/get-version.sh)"
	@echo "Build Number: Managed by Bitrise (BITRISE_BUILD_NUMBER)"
	@echo "Secrets: $$(if [ -f Convos/Config/Secrets.swift ]; then echo "✅ Generated"; else echo "❌ Missing"; fi)"
	@echo "Git: $$(git rev-parse --abbrev-ref HEAD) ($$(git rev-parse --short HEAD))"
	@echo "Environment: $$(if [ -f .env ]; then echo "✅ .env exists"; else echo "❌ No .env"; fi)"
	@echo ""
	@echo "🌍 Current Environment:"
	@echo "   • Local: org.convos.ios (local development, no CI)"
	@echo "   • Dev: org.convos.ios-preview (TestFlight internal, CI: dev branch)"
	@echo "   • Prod: org.convos.ios (App Store, CI: main branch)"

.PHONY: tag-release
tag-release: ## Create and push a release tag (triggers auto-PR creation)
	./Scripts/create-release-tag.sh

.PHONY: dry-run-release
dry-run-release: ## Test release workflow without making changes (dry run)
	@echo "🔍 DRY RUN MODE: Testing release workflow..."
	@echo "This will show what would happen without making actual changes."
	@echo ""
	@echo "To proceed with a real release, use: make tag-release"
	@echo ""
	@read -p "Press Enter to continue with dry run, or Ctrl+C to cancel... "
	./Scripts/create-release-tag.sh --dry-run

.PHONY: dry-run-release-quick
dry-run-release-quick: ## Quick dry run without user interaction
	@echo "🔍 QUICK DRY RUN: Testing release workflow..."
	@echo "This will simulate the release process without making changes."
	@echo ""
	./Scripts/create-release-tag.sh --dry-run
