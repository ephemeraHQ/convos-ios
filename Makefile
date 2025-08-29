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
	@echo ""
	@echo "🔧 Setup & Maintenance:"
	@echo "   make setup          - Setup development environment"
	@echo "   make clean          - Clean generated files"
	@echo "   make clean-all      - Clean all files and build artifacts"
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
	@echo "   2. Manual PR: dev → main (triggers production build)"
	@echo "   3. Main → App Store (after review and approval)"

.PHONY: setup
setup: ## Setup dependencies and developer environment
	./Scripts/setup.sh

.PHONY: secrets
secrets: ## Generate Secrets.swift (auto-detects environment)
	@if [ -n "$$CI" ] || [ -n "$$BITRISE" ]; then \
		echo "🔧 CI/CD environment detected, using secure secrets..."; \
		./Scripts/generate-secrets-secure.sh; \
	else \
		echo "🏠 Local environment detected, using local secrets..."; \
		./Scripts/generate-secrets-local.sh; \
	fi

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
	rm -f Convos/Convos.entitlements
	rm -f .env

.PHONY: clean-all
clean-all: ## Clean all generated files and build artifacts
	rm -f Convos/Config/Secrets.swift
	rm -f Convos/Convos.entitlements
	rm -f .env
	rm -rf build/
	rm -rf DerivedData/
	rm -rf *.xcarchive
	rm -rf *.ipa

.PHONY: status
status: ## Show project status (version, secrets, git)
	@echo "📱 Project Status"
	@echo "=================="
	@echo "Version: $(shell ./Scripts/get-version.sh)"
	@echo "Build Number: Managed by Bitrise (BITRISE_BUILD_NUMBER)"
	@echo "Secrets: $(shell if [ -f Convos/Config/Secrets.swift ]; then echo "✅ Generated"; else echo "❌ Missing"; fi)"
	@echo "Git: $(shell git rev-parse --abbrev-ref HEAD) ($(shell git rev-parse --short HEAD))"
	@echo "Environment: $(shell if [ -f .env ]; then echo "✅ .env exists"; else echo "❌ No .env"; fi)"
	@echo ""
	@echo "🌍 Current Environment:"
	@echo "   • Local: org.convos.ios (local development, no CI)"
	@echo "   • Dev: org.convos.ios-preview (TestFlight internal, CI: dev branch)"
	@echo "   • Prod: org.convos.ios (App Store, CI: main branch)"

