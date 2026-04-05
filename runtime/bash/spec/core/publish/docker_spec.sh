Describe "publish/docker.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/docker.sh"

  Describe "publish.docker.run"
    It "returns 2 for unknown option"
      When call publish.docker.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 when no image specified"
      When call publish.docker.run
      The status should equal 2
      The stderr should include "docker image name is required"
    End

    Describe "require_tool docker failure"
      setup_no_docker() {
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_docker() {
        export PATH="$ORIG_PATH"
        rm -rf "$MOCK_BIN"
      }
      Before 'setup_no_docker'
      After 'cleanup_no_docker'

      It "returns 3 when docker is not on PATH"
        When call publish.docker.run --image myapp
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock docker"
      setup_docker() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_docker.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/docker" << MOCKEOF
#!/usr/bin/env bash
printf 'docker %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/docker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_docker() {
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_DOCKER_IMAGE BRIK_PUBLISH_DOCKER_REGISTRY 2>/dev/null
        unset BRIK_PUBLISH_DOCKER_TAGS BRIK_PUBLISH_DOCKER_USERNAME_VAR BRIK_PUBLISH_DOCKER_PASSWORD_VAR 2>/dev/null
        unset BRIK_VERSION 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_docker'
      After 'cleanup_docker'

      It "pushes image with specified tag"
        invoke_push() {
          publish.docker.run --image "myapp" --tags "v1.0.0" 2>/dev/null || return 1
          grep -q "docker push myapp:v1.0.0" "$MOCK_LOG"
        }
        When call invoke_push
        The status should be success
      End

      It "defaults tags to BRIK_VERSION"
        invoke_version_tag() {
          export BRIK_VERSION="2.0.0"
          publish.docker.run --image "myapp" 2>/dev/null || return 1
          grep -q "docker push myapp:2.0.0" "$MOCK_LOG"
        }
        When call invoke_version_tag
        The status should be success
      End

      It "defaults tags to latest when no BRIK_VERSION"
        invoke_default_tag() {
          unset BRIK_VERSION 2>/dev/null
          publish.docker.run --image "myapp" 2>/dev/null || return 1
          grep -q "docker push myapp:latest" "$MOCK_LOG"
        }
        When call invoke_default_tag
        The status should be success
      End

      It "pushes multiple tags"
        invoke_multi_tag() {
          publish.docker.run --image "myapp" --tags "v1.0.0,latest" 2>/dev/null || return 1
          grep -q "docker push myapp:v1.0.0" "$MOCK_LOG" && grep -q "docker push myapp:latest" "$MOCK_LOG"
        }
        When call invoke_multi_tag
        The status should be success
      End

      It "logs in with credentials"
        invoke_login() {
          export DOCKER_USER="myuser"
          export DOCKER_PASS="mypass"
          publish.docker.run --image "myapp" --tags "v1.0.0" \
            --username-var "DOCKER_USER" --password-var "DOCKER_PASS" \
            --registry "registry.example.com" 2>/dev/null || return 1
          grep -q "docker login" "$MOCK_LOG"
        }
        When call invoke_login
        The status should be success
      End

      It "logs out after push when credentials were used"
        invoke_logout() {
          export DOCKER_USER="myuser"
          export DOCKER_PASS="mypass"
          publish.docker.run --image "myapp" --tags "v1.0.0" \
            --username-var "DOCKER_USER" --password-var "DOCKER_PASS" 2>/dev/null || return 1
          grep -q "docker logout" "$MOCK_LOG"
        }
        When call invoke_logout
        The status should be success
      End

      It "returns 7 when username_var references unset variable"
        When call publish.docker.run --image "myapp" --username-var "NONEXISTENT_USER" --password-var "NONEXISTENT_PASS"
        The status should equal 7
        The stderr should include "is not set or empty"
      End

      It "reads image from BRIK_PUBLISH_DOCKER_IMAGE"
        invoke_env_image() {
          export BRIK_PUBLISH_DOCKER_IMAGE="env-app"
          publish.docker.run --tags "v1.0.0" 2>/dev/null || return 1
          grep -q "docker push env-app:v1.0.0" "$MOCK_LOG"
        }
        When call invoke_env_image
        The status should be success
      End

      It "reads tags from BRIK_PUBLISH_DOCKER_TAGS"
        invoke_env_tags() {
          export BRIK_PUBLISH_DOCKER_TAGS="v2.0.0,edge"
          publish.docker.run --image "myapp" 2>/dev/null || return 1
          grep -q "docker push myapp:v2.0.0" "$MOCK_LOG" && grep -q "docker push myapp:edge" "$MOCK_LOG"
        }
        When call invoke_env_tags
        The status should be success
      End

      It "uses --dry-run flag"
        When call publish.docker.run --image "myapp" --tags "v1.0.0" --dry-run
        The status should be success
        The stderr should include "[dry-run] docker push myapp:v1.0.0"
      End

      It "does not call docker push in dry-run"
        invoke_no_push() {
          publish.docker.run --image "myapp" --tags "v1.0.0" --dry-run 2>/dev/null || return 1
          [[ ! -f "$MOCK_LOG" ]] || ! grep -q "^docker push" "$MOCK_LOG"
        }
        When call invoke_no_push
        The status should be success
      End

      It "reports success"
        When call publish.docker.run --image "myapp" --tags "v1.0.0"
        The status should be success
        The stderr should include "docker publish completed successfully"
      End
    End

    Describe "with failing docker push"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/docker" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "push" ]]; then exit 1; fi
exit 0
EOF
        chmod +x "${MOCK_BIN}/docker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when docker push fails"
        When call publish.docker.run --image "myapp" --tags "v1.0.0"
        The status should equal 5
        The stderr should include "docker push failed"
      End
    End

    Describe "with failing docker login"
      setup_login_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/docker" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "login" ]]; then exit 1; fi
exit 0
EOF
        chmod +x "${MOCK_BIN}/docker"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export DOCKER_USER="myuser"
        export DOCKER_PASS="mypass"
      }
      cleanup_login_fail() {
        export PATH="$ORIG_PATH"
        unset DOCKER_USER DOCKER_PASS
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_login_fail'
      After 'cleanup_login_fail'

      It "returns 5 when docker login fails"
        When call publish.docker.run --image "myapp" --tags "v1.0.0" \
          --username-var "DOCKER_USER" --password-var "DOCKER_PASS"
        The status should equal 5
        The stderr should include "docker login failed"
      End
    End
  End
End
