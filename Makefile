.PHONY: help lint test test-quick coverage validate check clean install uninstall

help: ## Show available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## Run shellcheck on all Bash sources
	shellcheck --severity=warning -x bin/brik $$(find runtime/bash/lib shared-libs -name '*.sh' -not -path '*/spec/*')

test: ## Run all ShellSpec tests
	shellspec

test-quick: ## Run tests, stop on first failure
	shellspec --fail-fast

coverage: ## Run tests with kcov coverage report
	ulimit -n 1024 && shellspec --kcov

validate: ## Validate example brik.yml files
	bin/brik validate --config examples/minimal-node/brik.yml
	bin/brik validate --config examples/java-maven/brik.yml
	bin/brik validate --config examples/python-pytest/brik.yml
	bin/brik validate --config examples/mono-dotnet/brik.yml

check: lint coverage validate ## Full pre-commit gate (lint + coverage + validate)

install: ## Install brik symlink into /usr/local/bin (dev mode)
	@if [ -f /usr/local/bin/brik ] && [ ! -L /usr/local/bin/brik ]; then \
		echo "error: /usr/local/bin/brik exists and is not a symlink"; \
		echo "hint: remove it first or set BRIK_HOME to override"; \
		exit 1; \
	fi
	ln -sf "$(CURDIR)/bin/brik" /usr/local/bin/brik
	@echo "installed: /usr/local/bin/brik -> $(CURDIR)/bin/brik"

uninstall: ## Remove brik symlink from /usr/local/bin
	rm -f /usr/local/bin/brik
	@echo "removed: /usr/local/bin/brik"

clean: ## Remove generated files
	rm -rf coverage/
