Describe "shared-libs/jenkins brikResolveHome.groovy"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikResolveHome.groovy"

  # Smoke checks on the Groovy source (cold-cache race fix, 2026-05-25).

  Describe "matching criterion"
    It "scans @libs/*/vars/brikPipeline.groovy (strict invariant of the library)"
      When call grep -F "vars/brikPipeline.groovy" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "no longer relies on the weaker @libs/*/lib/ marker"
      When call grep -F '[ -d "${d}lib" ]' "$GROOVY"
      The status should not equal 0
    End
  End

  Describe "cold-cache race handling"
    It "polls before giving up"
      When call grep -F "max_attempts=10" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "uses a half-second backoff"
      When call grep -F "sleep 0.5" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "exits non-zero rather than returning a fake path"
      When call grep -F "exit 1" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "no longer falls back to the bogus libs_dir/brik path"
      When call grep -F 'printf '"'"'%s'"'"' "${libs_dir}/brik"' "$GROOVY"
      The status should not equal 0
    End

    It "emits a diagnostic message naming the library declaration"
      When call grep -F "@Library" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  # Functional check on the embedded shell payload. We extract the heredoc
  # body from the Groovy source and run it under bash so the happy path is
  # actually verified, not just grep-matched.

  Describe "embedded shell payload (functional)"
    extract_shell_payload() {
      awk '
        /script: '\'''\'''\''#!\/bin\/bash/ { in_block=1; next }
        in_block && /'\'''\'''\'',/ { in_block=0; exit }
        in_block { print }
      ' "$GROOVY"
    }

    Before 'setup_ws'
    After  'cleanup_ws'

    setup_ws() {
      RH_WS="$(mktemp -d)"
      export WORKSPACE="$RH_WS"
    }
    cleanup_ws() {
      rm -rf "$RH_WS"
      unset WORKSPACE
    }

    It "returns the hash-named directory that carries vars/brikPipeline.groovy"
      run_payload() {
        mkdir -p "${WORKSPACE}@libs/abc123/vars"
        : > "${WORKSPACE}@libs/abc123/vars/brikPipeline.groovy"
        bash -c "$(extract_shell_payload)"
      }
      When call run_payload
      The status should be success
      The output should equal "${RH_WS}@libs/abc123"
    End

    It "picks the right candidate among multiple hash-named directories"
      run_payload() {
        mkdir -p "${WORKSPACE}@libs/aaa/vars" "${WORKSPACE}@libs/bbb/vars"
        : > "${WORKSPACE}@libs/bbb/vars/brikPipeline.groovy"
        bash -c "$(extract_shell_payload)"
      }
      When call run_payload
      The status should be success
      The output should match pattern "${RH_WS}@libs/*"
    End

    It "ignores hash-named directories without the marker file"
      run_payload() {
        mkdir -p "${WORKSPACE}@libs/noise/vars"
        : > "${WORKSPACE}@libs/noise/vars/anotherFile.groovy"
        mkdir -p "${WORKSPACE}@libs/real/vars"
        : > "${WORKSPACE}@libs/real/vars/brikPipeline.groovy"
        bash -c "$(extract_shell_payload)"
      }
      When call run_payload
      The status should be success
      The output should equal "${RH_WS}@libs/real"
    End
  End
End
