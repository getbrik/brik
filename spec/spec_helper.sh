#!/usr/bin/env bash
# spec_helper.sh - Common setup for ShellSpec test suites
#
# Loaded automatically via --require spec_helper in .shellspec.
# ShellSpec sets the execution directory to the project root (where .shellspec
# lives) before loading this file, so $(pwd) resolves to BRIK_HOME.
#
# Exported variables:
#   BRIK_HOME   - absolute path to the brik source repository root
#   BRIK_BIN    - absolute path to the brik CLI script
#   BRIK_SCHEMA - absolute path to the bundled JSON Schema
#   FIXTURES    - absolute path to the testdata/fixtures directory
#   EXAMPLES    - absolute path to the examples directory

spec_helper_precheck() {
  minimum_version "0.28.0"
}

spec_helper_loaded() {
  # Project root is the current directory when this helper is loaded.
  export BRIK_HOME
  BRIK_HOME="$(pwd)"

  # Isolate every spec from the developer's global / system git config.
  # Global keys like tag.gpgsign=true or commit.gpgsign=true would
  # otherwise leak into specs that exercise git operations (lightweight
  # tag, commit) and break them with "fatal: no tag message?" etc. By
  # routing GIT_CONFIG_GLOBAL to /dev/null and disabling system config,
  # every test sees a pristine git baseline regardless of the host setup.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1

  export BRIK_BIN="${BRIK_HOME}/bin/brik"
  export BRIK_SCHEMA="${BRIK_HOME}/schemas/config/v1/brik.schema.json"
  export FIXTURES="${BRIK_HOME}/testdata/fixtures"
  export EXAMPLES="${BRIK_HOME}/examples"

  # Runtime library paths (notion dirs, domain-driven layout).
  export BRIK_PIPELINE_LIB="${BRIK_HOME}/lib/pipeline"
  export BRIK_TRANSVERSE_LIB="${BRIK_HOME}/lib/transverse"
  export BRIK_STACKS_LIB="${BRIK_HOME}/lib/stacks"
  export BRIK_ROLLOUT_LIB="${BRIK_HOME}/lib/rollout"
  export BRIK_DEPLOYMENTS_LIB="${BRIK_HOME}/lib/deployments"
  export BRIK_PACKAGE_MANAGERS_LIB="${BRIK_HOME}/lib/package-managers"
  export BRIK_STAGES_LIB="${BRIK_HOME}/lib/stages"
  export BRIK_CLI_LIB="${BRIK_HOME}/lib/cli"
  # BRIK_LIB is an optional escape hatch (empty by default now that lib/core/
  # has been absorbed). Loader resolves via BRIK_LIB_EXTENSIONS.
  export BRIK_LIB=""
  export BRIK_LIB_EXTENSIONS="${BRIK_PIPELINE_LIB}:${BRIK_TRANSVERSE_LIB}:${BRIK_STACKS_LIB}:${BRIK_ROLLOUT_LIB}:${BRIK_DEPLOYMENTS_LIB}:${BRIK_PACKAGE_MANAGERS_LIB}:${BRIK_STAGES_LIB}:${BRIK_CLI_LIB}:${BRIK_HOME}/lib"
  export WORKSPACES="${FIXTURES}/workspaces"
}

spec_helper_configure() {
  # Temporary log directory for tests - cleaned up by ShellSpec
  export BRIK_LOG_DIR
  BRIK_LOG_DIR="$(mktemp -d)"

  # Exit code constants - required by all modules using BRIK_EXIT_* returns
  . "${BRIK_PIPELINE_LIB}/error.sh"
}
