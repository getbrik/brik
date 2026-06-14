.PHONY: help lint test test-quick coverage validate validate-docs regen-docs check-docs-drift check clean install uninstall metrics

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
	@# Clamp the fd limit to 1024. kcov uses select(), so a file
	@# descriptor at or above FD_SETSIZE (1024) is unusable; under a
	@# high limit such as the macOS default soft limit of 1048576 kcov
	@# aborts with "Failed to exchange stderr for pipe: Bad file
	@# descriptor". `ulimit -n 1024` both lowers a high default and
	@# raises a low one -- do not change it to a raise-only guard.
	ulimit -n 1024 && shellspec --kcov --shell "$(BASH_PATH)"

validate: ## Validate every example brik.yml against the schema
	@for cfg in examples/*/brik.yml; do \
		echo "validate $$cfg"; \
		bin/brik validate --config "$$cfg" || exit 1; \
	done

validate-docs: ## Validate every fenced ```yaml block in docs/reference/configuration/**/*.md
	./scripts/validate-docs.sh

regen-docs: ## Regenerate the auto-managed Quick reference tables from the schema
	./scripts/gen-config-reference.sh --apply --all

check-docs-drift: ## Verify the auto-managed tables match the schema (CI gate)
	./scripts/gen-config-reference.sh --check

check: lint coverage validate validate-docs check-docs-drift ## Full pre-commit gate (lint + coverage + validate + docs + drift)

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
