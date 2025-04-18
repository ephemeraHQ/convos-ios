.PHONY: help
help: ## Print help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' \
	$(MAKEFILE_LIST) | sort

.PHONY: setup
setup: ## Setup dependencies and developer environment
	./Scripts/setup.sh

.PHONY: secrets
secrets: ## Generate Secrets.swift from .env
	./Scripts/generate_secrets.sh

.PHONY: upload_symbols
upload_symbols: ## Upload symbols to Sentry
	# for local uploading, use like this: DSYM_DIR_PATH=/path/to/dSYM/dir make upload_symbols
	./Scripts/upload_symbols.sh

.PHONY: bump-version
bump-version: ## Bump version number in Xcode project, resets build number to 1
	./Scripts/bump-version.sh

.PHONY: bump-build
bump-build: ## Increment build number by 1 in Xcode project
	./Scripts/bump-build.sh

.PHONY: release
release: ## Create a release branch for a given version
	./Scripts/release.sh

.PHONY: secrets upload_symbols bump-version bump-build release