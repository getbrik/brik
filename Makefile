.PHONY: help lint test test-quick coverage validate validate-docs check clean install uninstall metrics

help: ## Show available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## Run shellcheck on all Bash sources
	shellcheck --severity=warning -x bin/brik $$(find lib shared-libs -name '*.sh' -not -path '*/spec/*')

SHELLSPEC_JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)

test: ## Run all ShellSpec tests (parallel)
	shellspec --jobs $(SHELLSPEC_JOBS)

test-quick: ## Run tests, stop on first failure
	shellspec --jobs $(SHELLSPEC_JOBS) --fail-fast

BASH_PATH ?= $(shell command -v bash)

coverage: ## Run tests with kcov coverage report (--jobs ignored: kcov disables parallelism)
	ulimit -n 1024 && shellspec --kcov --shell "$(BASH_PATH)"

validate: ## Validate example brik.yml files
	bin/brik validate --config examples/minimal-node/brik.yml
	bin/brik validate --config examples/java-maven/brik.yml
	bin/brik validate --config examples/python-pytest/brik.yml
	bin/brik validate --config examples/mono-dotnet/brik.yml

validate-docs: ## Validate every fenced ```yaml block in docs/config/**/*.md
	./scripts/validate-docs.sh

check: lint coverage validate validate-docs ## Full pre-commit gate (lint + coverage + validate + docs)

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

metrics: ## Run shellmetrics on production scripts
	@find lib shared-libs -name '*.sh' -not -path '*/spec/*' | \
		xargs shellmetrics

clean: ## Remove generated files
	rm -rf coverage/
