.PHONY: help
help: ## Print help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' \
	$(MAKEFILE_LIST) | sort

.PHONY: secrets
secrets: ## Generate Secrets.swift from .env
	./Scripts/generate_secrets.sh

.PHONY: upload_symbols
upload_symbols: ## Upload symbols to Sentry
	# for local uploading, use like this: DSYM_DIR_PATH=/path/to/dSYM/dir make upload_symbols
	./Scripts/upload_symbols.sh

.PHONY: secrets