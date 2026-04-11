#!/usr/bin/env bash
# mock_helper.sh - Shared mock utilities for ShellSpec tests
#
# Provides a standard API for creating mock executables, managing PATH
# isolation, and verifying mock invocations. Include this file in spec
# files that need to mock external commands.
#
# Usage:
#   Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"
#
# Core lifecycle:
#   mock.setup            - Create mock bin dir, save original PATH
#   mock.cleanup          - Restore PATH, remove mock bin dir
#
# Mock creation (simple):
#   mock.create           - Silent mock that logs calls to MOCK_LOG
#   mock.create_failing   - Mock that exits 1 and logs calls
#   mock.create_output    - Mock that echoes fixed text
#   mock.create_echo      - Mock that echoes "mock <name>: <args>"
#   mock.create_logging   - Mock that logs calls to a custom log file
#
# Mock creation (advanced):
#   mock.create_script    - Mock with custom body (for conditionals, side effects)
#   mock.create_exit      - Silent mock with custom exit code
#
# Batch creation:
#   mock.create_many      - Create multiple silent mocks at once
#   mock.create_many_echo - Create multiple echo mocks at once
#   mock.pipeline_tools   - Create mocks for standard pipeline tools
#
# PATH management:
#   mock.activate         - Prepend MOCK_BIN to PATH
#   mock.isolate          - Replace PATH with MOCK_BIN only
#   mock.preserve_cmds    - Symlink essential system commands into mock bin
#
# Assertions:
#   mock.was_called       - Check if a mock was invoked (via MOCK_LOG)
#   mock.call_args        - Get the arguments a mock was called with
#   mock.call_count       - Count how many times a mock was called
#
# Workspace:
#   mock.workspace        - Create a temporary workspace directory

# Guard against double-sourcing
[[ -n "${_BRIK_MOCK_HELPER_LOADED:-}" ]] && return 0
_BRIK_MOCK_HELPER_LOADED=1

# -- State variables (set by mock.setup, used by other functions) ----------

MOCK_BIN=""
MOCK_LOG=""
_MOCK_ORIG_PATH=""
_MOCK_ORIG_PLATFORM=""
_MOCK_ORIG_BRIK_HOME=""

# -- Core lifecycle --------------------------------------------------------

# Create a mock bin directory and save original PATH.
# Call BEFORE restricting PATH.
mock.setup() {
  MOCK_BIN="$(mktemp -d)"
  MOCK_LOG="${MOCK_BIN}/_commands.log"
  : > "$MOCK_LOG"
  _MOCK_ORIG_PATH="$PATH"
  _MOCK_ORIG_PLATFORM="${BRIK_PLATFORM:-}"
  _MOCK_ORIG_BRIK_HOME="${BRIK_HOME:-}"
}

# Restore PATH and clean up mock bin directory.
mock.cleanup() {
  PATH="$_MOCK_ORIG_PATH"
  export BRIK_PLATFORM="$_MOCK_ORIG_PLATFORM"
  export BRIK_HOME="$_MOCK_ORIG_BRIK_HOME"
  [[ -n "$MOCK_BIN" ]] && rm -rf "$MOCK_BIN"
  MOCK_BIN=""
  MOCK_LOG=""
}

# -- Mock creation (simple) ------------------------------------------------

# Create a silent mock executable that logs its invocation to MOCK_LOG.
# Usage: mock.create <name>
mock.create() {
  local name="$1"
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# Create a mock that always fails (exit 1) and logs to MOCK_LOG.
# Usage: mock.create_failing <name>
mock.create_failing() {
  local name="$1"
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# Create a mock that echoes fixed text and exits with given code.
# Usage: mock.create_output <name> <output> [exit_code]
mock.create_output() {
  local name="$1"
  local output="$2"
  local exit_code="${3:-0}"
  printf '#!/bin/sh\necho "%s"\nexit %d\n' "$output" "$exit_code" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# Create a mock that echoes "mock <name>: <args>" to stdout.
# Replaces the inline heredoc pattern: echo "mock npm: $*"
# Usage: mock.create_echo <name>
mock.create_echo() {
  local name="$1"
  printf '#!/bin/sh\necho "mock %s: $*"\n' "$name" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# Create a mock that logs calls via printf to a custom log file.
# Replaces the inline pattern: printf 'name %s\n' "$*" >> "$MOCK_LOG"
# Usage: mock.create_logging <name> <log_file>
mock.create_logging() {
  local name="$1"
  local log_file="$2"
  printf "#!/bin/sh\nprintf '%s %%s\\n' \"\$*\" >> \"%s\"\n" "$name" "$log_file" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# Create a silent mock that exits with a custom code (no output, no logging).
# Usage: mock.create_exit <name> <exit_code>
mock.create_exit() {
  local name="$1"
  local exit_code="$2"
  printf '#!/bin/sh\nexit %d\n' "$exit_code" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# -- Mock creation (advanced) ---------------------------------------------

# Create a mock with a custom script body.
# Use for conditional logic, side effects, or any non-standard behavior.
# Usage: mock.create_script <name> <body>
# Example:
#   mock.create_script "npm" '
#     if [ "$1" = "install" ]; then mkdir -p node_modules; fi
#     exit 0
#   '
mock.create_script() {
  local name="$1"
  local body="$2"
  printf '#!/bin/sh\n%s\n' "$body" > "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

# -- Batch creation --------------------------------------------------------

# Create multiple silent mocks at once (each logs to MOCK_LOG).
# Usage: mock.create_many <name1> <name2> ...
mock.create_many() {
  local name
  for name in "$@"; do
    mock.create "$name"
  done
}

# Create multiple echo mocks at once.
# Usage: mock.create_many_echo <name1> <name2> ...
mock.create_many_echo() {
  local name
  for name in "$@"; do
    mock.create_echo "$name"
  done
}

# Create mocks for standard pipeline tools (npm, node, npx, semgrep,
# osv-scanner, gitleaks). Covers the common setup in CLI pipeline tests.
# Usage: mock.pipeline_tools
mock.pipeline_tools() {
  mock.create_echo "npm"
  mock.create_exit "node" 0
  mock.create_echo "npx"
  local tool
  for tool in semgrep osv-scanner gitleaks; do
    mock.create_echo "$tool"
  done
}

# -- PATH management -------------------------------------------------------

# Prepend MOCK_BIN to PATH (keeps system commands available).
mock.activate() {
  export PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
}

# Replace PATH entirely with MOCK_BIN (full isolation).
# Call mock.preserve_cmds first to keep essential commands.
mock.isolate() {
  export PATH="${MOCK_BIN}"
}

# Preserve essential system commands in MOCK_BIN as symlinks.
# Call BEFORE mock.isolate so that filtered directories do not
# remove commands needed by the code under test.
mock.preserve_cmds() {
  local cmd cmd_path
  for cmd in mkdir chmod date tr rm cat basename dirname printf sed grep awk wc head tail tee sort uniq; do
    cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
    if [[ -n "$cmd_path" && ! -e "${MOCK_BIN}/${cmd}" ]]; then
      ln -s "$cmd_path" "${MOCK_BIN}/${cmd}"
    fi
  done
}

# -- Assertions ------------------------------------------------------------

# Check if a mock was called at least once.
# Usage: mock.was_called <name>
mock.was_called() {
  local name="$1"
  grep -q "^${name} " "$MOCK_LOG" 2>/dev/null
}

# Get the arguments from the last invocation of a mock.
# Usage: mock.call_args <name>
mock.call_args() {
  local name="$1"
  grep "^${name} " "$MOCK_LOG" 2>/dev/null | tail -1 | sed "s/^${name} //"
}

# Count how many times a mock was called.
# Usage: mock.call_count <name>
mock.call_count() {
  local name="$1" count
  count="$(grep -c "^${name} " "$MOCK_LOG" 2>/dev/null)" || count=0
  echo "$count"
}

# -- Workspace helpers -----------------------------------------------------

# Create a temporary workspace directory.
# Usage: local ws; ws="$(mock.workspace)"
mock.workspace() {
  mktemp -d
}
