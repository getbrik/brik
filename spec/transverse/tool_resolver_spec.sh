#shellcheck shell=bash
# Contract for lib/transverse/tool_resolver.sh
#
# The tool resolver consolidates the "where does this binary come from?"
# question that today appears inline in every lint/test/format stage:
#
#   1. <BRIK_WORKSPACE>/node_modules/.bin/<tool>  -> provenance=project
#   2. command -v <tool> (i.e. $PATH)             -> provenance=image
#   3. <BRIK_HOME>/tools/<tool>                   -> provenance=bundled
#   4. not found anywhere                         -> provenance=missing
#
# Public API:
#   tool_resolver.resolve <tool>      -> stdout JSON
#                                         {path, version, provenance}
#                                        rc=0 always except empty tool name
#   tool_resolver.is_available <tool> -> stdout "true"|"false", rc=0
#
# Version detection is best-effort: the resolver invokes `<path> --version`,
# strips ANSI, and keeps the first whitespace-separated semver-like token
# from the first line. On missing/uncooperative tools it reports "unknown".

Describe "lib/transverse/tool_resolver.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"
  Include "$BRIK_HOME/lib/transverse/tool_resolver.sh"

  setup_resolver() {
    mock.setup
    WS="$(mock.workspace)"
    BUNDLED="$(mktemp -d)"
    SAVED_HOME="${BRIK_HOME:-}"
    SAVED_WS="${BRIK_WORKSPACE:-}"
    export BRIK_WORKSPACE="$WS"
    # Override BRIK_HOME locally so tests target our throwaway tools dir.
    # The real BRIK_HOME (the brik checkout) is preserved by SAVED_HOME.
    export BRIK_HOME="$BUNDLED"
    mkdir -p "$BUNDLED/tools"
    mock.preserve_cmds
    mock.isolate
  }
  cleanup_resolver() {
    mock.cleanup
    rm -rf "$WS" "$BUNDLED"
    export BRIK_WORKSPACE="$SAVED_WS"
    export BRIK_HOME="$SAVED_HOME"
  }

  Before 'setup_resolver'
  After  'cleanup_resolver'

  Describe "tool_resolver.resolve"
    It "returns provenance=missing when the tool exists nowhere"
      do_resolve() {
        tool_resolver.resolve "no-such-tool"
      }
      When call do_resolve
      The output should include '"provenance":"missing"'
      The output should include '"path":""'
      The output should include '"version":"unknown"'
      The status should equal 0
    End

    It "prefers the workspace node_modules/.bin entry"
      do_resolve() {
        mkdir -p "$WS/node_modules/.bin"
        printf '#!/bin/sh\necho "v8.57.0"\n' > "$WS/node_modules/.bin/eslint"
        chmod +x "$WS/node_modules/.bin/eslint"
        tool_resolver.resolve "eslint"
      }
      When call do_resolve
      The output should include '"provenance":"project"'
      The output should include "node_modules/.bin/eslint"
      The output should include '"version":"8.57.0"'
    End

    It "falls back to PATH when the workspace has no local copy"
      do_resolve() {
        mock.create_output "ruff" "ruff 0.6.9"
        tool_resolver.resolve "ruff"
      }
      When call do_resolve
      The output should include '"provenance":"image"'
      The output should include '"version":"0.6.9"'
    End

    It "falls back to bundled when PATH has no entry"
      do_resolve() {
        printf '#!/bin/sh\necho "widget 1.2.3"\n' > "$BUNDLED/tools/widget"
        chmod +x "$BUNDLED/tools/widget"
        tool_resolver.resolve "widget"
      }
      When call do_resolve
      The output should include '"provenance":"bundled"'
      The output should include "/tools/widget"
      The output should include '"version":"1.2.3"'
    End

    It "still reports a path when the tool is silent about its version"
      do_resolve() {
        mkdir -p "$WS/node_modules/.bin"
        printf '#!/bin/sh\nexit 0\n' > "$WS/node_modules/.bin/silent"
        chmod +x "$WS/node_modules/.bin/silent"
        tool_resolver.resolve "silent"
      }
      When call do_resolve
      The output should include '"provenance":"project"'
      The output should include '"version":"unknown"'
    End

    It "rejects an empty tool name with rc=2"
      do_resolve_empty() {
        tool_resolver.resolve ""
      }
      When call do_resolve_empty
      The status should equal 2
      The stderr should include "tool name is required"
    End
  End

  Describe "tool_resolver.is_available"
    It "returns true when the tool is on PATH"
      do_avail() {
        mock.create_exit "found" 0
        tool_resolver.is_available "found"
      }
      When call do_avail
      The output should equal "true"
      The status should equal 0
    End

    It "returns true when the tool is in workspace node_modules/.bin"
      do_avail() {
        mkdir -p "$WS/node_modules/.bin"
        printf '#!/bin/sh\nexit 0\n' > "$WS/node_modules/.bin/local-only"
        chmod +x "$WS/node_modules/.bin/local-only"
        tool_resolver.is_available "local-only"
      }
      When call do_avail
      The output should equal "true"
    End

    It "returns true when the tool is bundled"
      do_avail() {
        printf '#!/bin/sh\nexit 0\n' > "$BUNDLED/tools/bundled-only"
        chmod +x "$BUNDLED/tools/bundled-only"
        tool_resolver.is_available "bundled-only"
      }
      When call do_avail
      The output should equal "true"
    End

    It "returns false for a tool that is nowhere"
      do_avail() {
        tool_resolver.is_available "absolutely-not-here"
      }
      When call do_avail
      The output should equal "false"
      The status should equal 0
    End

    It "rejects an empty tool name with rc=2"
      do_avail_empty() {
        tool_resolver.is_available ""
      }
      When call do_avail_empty
      The status should equal 2
      The stderr should include "tool name is required"
    End
  End

  Describe "resolution priority"
    It "project beats image and bundled when all three exist"
      do_resolve() {
        mkdir -p "$WS/node_modules/.bin"
        printf '#!/bin/sh\necho project 1.0.0\n' > "$WS/node_modules/.bin/clash"
        chmod +x "$WS/node_modules/.bin/clash"
        mock.create_output "clash" "image 2.0.0"
        printf '#!/bin/sh\necho bundled 3.0.0\n' > "$BUNDLED/tools/clash"
        chmod +x "$BUNDLED/tools/clash"
        tool_resolver.resolve "clash"
      }
      When call do_resolve
      The output should include '"provenance":"project"'
      The output should include '"version":"1.0.0"'
    End

    It "image beats bundled when project is absent"
      do_resolve() {
        mock.create_output "duo" "image 2.0.0"
        printf '#!/bin/sh\necho bundled 3.0.0\n' > "$BUNDLED/tools/duo"
        chmod +x "$BUNDLED/tools/duo"
        tool_resolver.resolve "duo"
      }
      When call do_resolve
      The output should include '"provenance":"image"'
      The output should include '"version":"2.0.0"'
    End
  End

  Describe "BRIK_WORKSPACE fallback"
    It "uses pwd when BRIK_WORKSPACE is unset"
      do_resolve_unset_ws() {
        unset BRIK_WORKSPACE
        cd "$WS" || return 1
        mkdir -p node_modules/.bin
        printf '#!/bin/sh\necho 9.9.9\n' > node_modules/.bin/here
        chmod +x node_modules/.bin/here
        tool_resolver.resolve "here"
      }
      When call do_resolve_unset_ws
      The output should include '"provenance":"project"'
      The output should include '"version":"9.9.9"'
    End
  End
End
