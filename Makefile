.DEFAULT_GOAL := help
.PHONY: help build debug run test dist clean cert icon

help: ## List available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-6s %s\n", $$1, $$2}'

build: ## Build release build/Notch.app (signed with the local certificate if any, else ad hoc)
	@scripts/build-app.sh release

debug: ## Build debug build/Notch.app
	@scripts/build-app.sh debug

run: build ## Build, then (re)launch the app; pass app args with ARGS="-NotchDebugState expanded"
	@scripts/run.sh $(ARGS)

test: ## Run unit tests
	@scripts/test.sh

dist: build ## Zip the app into build/dist/Notch-<version>.zip
	@scripts/package.sh

clean: ## Remove .build and build
	rm -rf .build build

cert: ## Create the local signing certificate that keeps Accessibility access across builds
	@scripts/create-signing-cert.sh

icon: ## Regenerate Resources/AppIcon.icns from Resources/AppIcon.svg
	@scripts/make-icon.sh
