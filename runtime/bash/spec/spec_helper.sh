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

  export BRIK_BIN="${BRIK_HOME}/bin/brik"
  export BRIK_SCHEMA="${BRIK_HOME}/schemas/config/v1/brik.schema.json"
  export FIXTURES="${BRIK_HOME}/testdata/fixtures"
  export EXAMPLES="${BRIK_HOME}/examples"
}

spec_helper_configure() {
  :
}
