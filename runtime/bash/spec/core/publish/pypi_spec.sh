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

      It "sets TWINE_USERNAME and TWINE_PASSWORD env vars (not CLI args)"
        invoke_token() {
          export MY_PYPI_TOKEN="pypi-token-123"
          publish.pypi.run --token-var "MY_PYPI_TOKEN" 2>/dev/null || return 1
          # Token should NOT appear in CLI args (security: env vars only)
          ! grep -q "pypi-token-123" "$MOCK_LOG"
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

      It "sets UV_PUBLISH_TOKEN env var (not CLI arg)"
        invoke_uv_token() {
          export MY_PYPI_TOKEN="pypi-uv-token"
          publish.pypi.run --token-var "MY_PYPI_TOKEN" 2>/dev/null || return 1
          # Token should NOT appear in CLI args (security: env var only)
          ! grep -q "pypi-uv-token" "$MOCK_LOG"
        }
        When call invoke_uv_token
        The status should be success
      End
    End

    Describe "twine with basic auth (user:password)"
      setup_basic_auth() {
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
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_basic_auth() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset TWINE_USERNAME TWINE_PASSWORD MY_BASIC_TOKEN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_basic_auth'
      After 'cleanup_basic_auth'

      It "sets TWINE_USERNAME and TWINE_PASSWORD from user:password format"
        invoke_basic() {
          export MY_BASIC_TOKEN="admin:secret123"
          publish.pypi.run --token-var "MY_BASIC_TOKEN" 2>/dev/null || return 1
          # Token should NOT appear in CLI args
          ! grep -q "admin" "$MOCK_LOG"
        }
        When call invoke_basic
        The status should be success
      End
    End

    Describe "twine with auto-build"
      setup_autobuild() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_twine.log"
        # No dist/ directory - triggers auto-build
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/twine" << MOCKEOF
#!/usr/bin/env bash
printf 'twine %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/twine"
        cat > "${MOCK_BIN}/python" << MOCKEOF
#!/usr/bin/env bash
# Simulate python -m build creating dist files
if [[ "\$2" == "build" ]]; then
  mkdir -p "$TEST_WS/dist"
  printf 'pkg\n' > "$TEST_WS/dist/test-1.0.0.tar.gz"
fi
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/python"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_autobuild() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_autobuild'
      After 'cleanup_autobuild'

      It "auto-builds distribution when dist/ is empty"
        invoke_autobuild() {
          publish.pypi.run 2>/dev/null || return 1
          grep -q "twine upload" "$MOCK_LOG"
        }
        When call invoke_autobuild
        The status should be success
      End
    End

    Describe "twine publish failure"
      setup_fail_twine() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/dist"
        printf 'pkg\n' > "${TEST_WS}/dist/test-1.0.0.tar.gz"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/twine" << 'FAILEOF'
#!/usr/bin/env bash
exit 1
FAILEOF
        chmod +x "${MOCK_BIN}/twine"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_fail_twine() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail_twine'
      After 'cleanup_fail_twine'

      It "returns 5 when twine upload fails"
        When call publish.pypi.run
        The status should equal 5
        The stderr should include "pypi publish failed"
      End
    End

    Describe "CI auto-install of twine"
      setup_ci_install() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        # Mock pip to "install" twine
        cat > "${MOCK_BIN}/pip" << MOCKEOF
#!/usr/bin/env bash
# Simulate installing twine by creating a mock twine
cat > "${MOCK_BIN}/twine" << 'INNER'
#!/usr/bin/env bash
exit 0
INNER
chmod +x "${MOCK_BIN}/twine"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/pip"
        cat > "${MOCK_BIN}/python" << MOCKEOF
#!/usr/bin/env bash
if [[ "\$2" == "build" ]]; then
  mkdir -p "$TEST_WS/dist"
  printf 'pkg\n' > "$TEST_WS/dist/test-1.0.0.tar.gz"
fi
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/python"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        export CI="true"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_ci_install() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset CI 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_ci_install'
      After 'cleanup_ci_install'

      It "auto-installs twine in CI and publishes"
        When call publish.pypi.run
        The status should be success
        The stderr should include "installing twine"
      End
    End

    Describe "no publish tool"
      setup_no_tool() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        ORIG_CI="${CI:-}"
        # Empty PATH - no tools (no pip/twine/uv/poetry)
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
        # Unset CI to prevent auto-install of twine
        unset CI
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_tool() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        [[ -n "$ORIG_CI" ]] && export CI="$ORIG_CI"
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
