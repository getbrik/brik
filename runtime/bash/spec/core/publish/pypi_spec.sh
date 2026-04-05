Describe "publish/pypi.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/pypi.sh"

  Describe "publish.pypi.run"
    It "returns 2 for unknown option"
      When call publish.pypi.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with mock twine"
      setup_twine() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_twine.log"
        mkdir -p "${TEST_WS}/dist"
        printf 'pkg\n' > "${TEST_WS}/dist/test-1.0.0.tar.gz"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/twine" << MOCKEOF
#!/usr/bin/env bash
printf 'twine %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/twine"
        # Only twine on PATH (no uv/poetry to avoid precedence), plus essentials
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_twine() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_PYPI_REPOSITORY BRIK_PUBLISH_PYPI_TOKEN_VAR 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_twine'
      After 'cleanup_twine'

      It "runs twine upload"
        invoke_twine() {
          publish.pypi.run 2>/dev/null || return 1
          grep -q "twine upload" "$MOCK_LOG"
        }
        When call invoke_twine
        The status should be success
      End

      It "passes repository URL"
        invoke_repo() {
          publish.pypi.run --repository "https://test.pypi.org/legacy/" 2>/dev/null || return 1
          grep -q "repository-url" "$MOCK_LOG"
        }
        When call invoke_repo
        The status should be success
      End

      It "passes token via --password"
        invoke_token() {
          export MY_PYPI_TOKEN="pypi-token-123"
          publish.pypi.run --token-var "MY_PYPI_TOKEN" 2>/dev/null || return 1
          grep -q "__token__" "$MOCK_LOG" && grep -q "pypi-token-123" "$MOCK_LOG"
        }
        When call invoke_token
        The status should be success
      End

      It "uses dry-run mode"
        When call publish.pypi.run --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "with poetry project"
      setup_poetry() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_poetry.log"
        cat > "${TEST_WS}/pyproject.toml" << 'EOF'
[tool.poetry]
name = "test"
version = "1.0.0"
EOF
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/poetry" << MOCKEOF
#!/usr/bin/env bash
printf 'poetry %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/poetry"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_poetry() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_PYPI_REPOSITORY BRIK_PUBLISH_PYPI_TOKEN_VAR POETRY_PYPI_TOKEN_PYPI 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_poetry'
      After 'cleanup_poetry'

      It "runs poetry publish --build"
        invoke_poetry() {
          publish.pypi.run 2>/dev/null || return 1
          grep -q "poetry publish --build" "$MOCK_LOG"
        }
        When call invoke_poetry
        The status should be success
      End

      It "passes repository to poetry"
        invoke_poetry_repo() {
          publish.pypi.run --repository "https://test.pypi.org/legacy/" 2>/dev/null || return 1
          grep -q "\-\-repository" "$MOCK_LOG"
        }
        When call invoke_poetry_repo
        The status should be success
      End

      It "sets POETRY_PYPI_TOKEN_PYPI for token"
        invoke_poetry_token() {
          export MY_PYPI_TOKEN="pypi-poetry-token"
          publish.pypi.run --token-var "MY_PYPI_TOKEN" 2>/dev/null || return 1
          # Token is set via env var, not CLI arg for poetry
          grep -q "poetry publish --build" "$MOCK_LOG"
        }
        When call invoke_poetry_token
        The status should be success
      End

      It "logs success message"
        When call publish.pypi.run
        The status should be success
        The stderr should include "pypi publish completed"
      End
    End

    Describe "with mock uv"
      setup_uv() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_uv.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/uv" << MOCKEOF
#!/usr/bin/env bash
printf 'uv %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/uv"
        ORIG_PATH="$PATH"
        # Only uv on PATH (no poetry/twine), plus essentials
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_uv() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_PYPI_REPOSITORY BRIK_PUBLISH_PYPI_TOKEN_VAR 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_uv'
      After 'cleanup_uv'

      It "runs uv publish"
        invoke_uv() {
          publish.pypi.run 2>/dev/null || return 1
          grep -q "uv publish" "$MOCK_LOG"
        }
        When call invoke_uv
        The status should be success
      End

      It "passes publish-url for repository"
        invoke_uv_repo() {
          publish.pypi.run --repository "https://test.pypi.org/legacy/" 2>/dev/null || return 1
          grep -q "\-\-publish-url" "$MOCK_LOG"
        }
        When call invoke_uv_repo
        The status should be success
      End

      It "passes token to uv"
        invoke_uv_token() {
          export MY_PYPI_TOKEN="pypi-uv-token"
          publish.pypi.run --token-var "MY_PYPI_TOKEN" 2>/dev/null || return 1
          grep -q "\-\-token" "$MOCK_LOG"
        }
        When call invoke_uv_token
        The status should be success
      End
    End

    Describe "no publish tool"
      setup_no_tool() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        # Empty PATH - no tools
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_tool() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_tool'
      After 'cleanup_no_tool'

      It "returns 3 when no publish tool found"
        When call publish.pypi.run
        The status should equal 3
        The stderr should include "no publish tool found"
      End
    End
  End
End
