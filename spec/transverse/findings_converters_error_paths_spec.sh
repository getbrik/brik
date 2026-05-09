#shellcheck shell=bash
# Error-path coverage for the findings.converters.<tool>.to_sarif family.
#
# The happy paths are exercised by findings_converters_{junit,python,p5d}_spec.sh
# via findings.from_json. The dispatcher validates arguments before calling
# the converter, so the converters' own error branches (missing args, missing
# jq, mv/cannot-write) are only reachable through a direct call.
#
# This spec calls each converter directly to lift them out of the 56% kcov
# range by walking the three uniform error branches:
#   1. missing arguments  -> BRIK_EXIT_INVALID_INPUT
#   2. jq missing         -> BRIK_EXIT_MISSING_DEP
#   3. mv failure         -> BRIK_EXIT_IO_FAILURE
#
# junit also has yq-missing + yq-failed-to-parse branches; those are
# covered alongside the shared three.

Describe "transverse/findings/converters/* error paths"
  Include "$BRIK_HOME/lib/transverse/findings/converters/bandit.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/clippy.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/dockle.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/junit.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/ruff.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/scancode.sh"
  Include "$BRIK_HOME/lib/transverse/findings/converters/trufflehog.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_err() {
    ERR_TMP="$(mktemp -d)"
    INPUT="${ERR_TMP}/in.json"
    OUTPUT="${ERR_TMP}/out.sarif"
    printf '[]\n' > "$INPUT"
  }
  cleanup_err() {
    rm -rf "$ERR_TMP"
  }
  Before 'setup_err'
  After  'cleanup_err'

  # -- missing-arguments branch (uniform across all converters) -------------

  Describe "missing arguments"
    Parameters
      bandit
      clippy
      dockle
      junit
      ruff
      scancode
      trufflehog
    End

    It "findings.converters.$1.to_sarif rejects empty argv with rc=2"
      run_no_args() {
        "findings.converters.$1.to_sarif"
      }
      When call run_no_args "$1"
      The status should equal 2
      The stderr should include "missing arguments"
    End

    It "findings.converters.$1.to_sarif rejects single-arg call with rc=2"
      run_one_arg() {
        "findings.converters.$1.to_sarif" "/tmp/only-input"
      }
      When call run_one_arg "$1"
      The status should equal 2
      The stderr should include "missing arguments"
    End
  End

  # -- jq-missing branch (uniform across all converters) -------------------

  Describe "jq missing"
    Parameters
      bandit
      clippy
      dockle
      ruff
      scancode
      trufflehog
    End

    setup_no_jq() {
      mock.setup
      mock.isolate
    }
    cleanup_no_jq() {
      mock.cleanup
    }
    Before 'setup_no_jq'
    After  'cleanup_no_jq'

    It "findings.converters.$1.to_sarif fails with rc=3 when jq is missing"
      run_no_jq() {
        "findings.converters.$1.to_sarif" "$INPUT" "$OUTPUT"
      }
      When call run_no_jq "$1"
      The status should equal 3
      The stderr should include "jq is required"
    End
  End

  Describe "junit yq missing"
    setup_no_yq() {
      mock.setup
      mock.isolate
    }
    cleanup_no_yq() { mock.cleanup; }
    Before 'setup_no_yq'
    After  'cleanup_no_yq'

    It "findings.converters.junit.to_sarif fails with rc=3 when yq is missing"
      run_no_yq() {
        findings.converters.junit.to_sarif "$INPUT" "$OUTPUT"
      }
      When call run_no_yq
      The status should equal 3
      The stderr should include "yq is required"
    End
  End

  Describe "junit yq parse failure"
    It "fails with rc=7 on malformed XML input"
      junit_bad_xml() {
        local bad="${ERR_TMP}/bad.xml"
        printf 'not<<<<<<<<XML\n' > "$bad"
        findings.converters.junit.to_sarif "$bad" "$OUTPUT"
      }
      When call junit_bad_xml
      The status should equal 7
      The stderr should include "failed to parse"
    End
  End

  # junit's jq-missing branch: yq present, jq absent. mock.isolate hides
  # system PATH, then a yq stub satisfies the yq probe so the function
  # reaches the jq probe and fails there.
  Describe "junit jq missing (with yq present)"
    setup_no_jq_yq_present() {
      mock.setup
      mock.create_exit "yq" 0
      mock.isolate
    }
    cleanup_no_jq_yq_present() { mock.cleanup; }
    Before 'setup_no_jq_yq_present'
    After  'cleanup_no_jq_yq_present'

    It "findings.converters.junit.to_sarif fails with rc=3 when only jq is missing"
      run_junit_no_jq() {
        findings.converters.junit.to_sarif "$INPUT" "$OUTPUT"
      }
      When call run_junit_no_jq
      The status should equal 3
      The stderr should include "jq is required"
    End
  End

  # junit's cannot-write branch: aim the output at a path whose parent is
  # a regular file so mv fails.
  Describe "junit cannot write output"
    It "fails when mv cannot write the output"
      run_junit_bad_dest() {
        local fixture="$BRIK_HOME/spec/fixtures/junit/mixed.xml"
        local blocker="${ERR_TMP}/blocker"
        : > "$blocker"
        local bad_out="${blocker}/out.sarif"
        findings.converters.junit.to_sarif "$fixture" "$bad_out"
      }
      When call run_junit_bad_dest
      The status should not equal 0
      The stderr should be present
    End
  End

  # -- cannot-write (mv failure) branch -------------------------------------
  #
  # Aim the output at a path whose parent is a regular file (not a
  # directory) so the helper's mv step fails.

  Describe "cannot write output"
    Parameters
      "bandit"   "bandit-empty.json"
      "clippy"   "clippy.ndjson"
      "dockle"   "dockle.json"
      "ruff"     "ruff-empty.json"
      "scancode" "scancode.json"
      "trufflehog" "trufflehog.ndjson"
    End

    It "findings.converters.$1.to_sarif fails when mv cannot write"
      run_bad_dest() {
        local input="$BRIK_HOME/spec/fixtures/json/$2"
        local blocker="${ERR_TMP}/blocker"
        : > "$blocker"
        local bad_out="${blocker}/out.sarif"
        "findings.converters.$1.to_sarif" "$input" "$bad_out"
      }
      When call run_bad_dest "$1" "$2"
      The status should not equal 0
      The stderr should be present
    End
  End
End
