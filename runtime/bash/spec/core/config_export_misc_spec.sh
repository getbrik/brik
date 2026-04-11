Describe "config.sh - export extended and misc vars"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.export_build_vars - dotnet/rust versions
  # =========================================================================
  Describe "config.export_build_vars dotnet version"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: dotnet
build:
  dotnet_version: "8.0"
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_DOTNET_VERSION"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_DOTNET_VERSION:-}"
      }
      When call export_and_check
      The output should equal "8.0"
    End
  End

  Describe "config.export_build_vars rust version"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: rust
build:
  rust_version: "1.75"
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_RUST_VERSION"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_RUST_VERSION:-}"
      }
      When call export_and_check
      The output should equal "1.75"
    End
  End

  # =========================================================================
  # config.export_quality_vars - extended fields
  # =========================================================================
  Describe "config.export_quality_vars extended fields"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
    config: .eslintrc.json
    fix: "true"
    command: npx eslint .
  format:
    tool: prettier
    check: true
    command: npx prettier --check .
  type_check:
    tool: tsc
    command: npx tsc --noEmit
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_QUALITY_FORMAT_CHECK"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_FORMAT_CHECK:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_QUALITY_LINT_CONFIG"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LINT_CONFIG:-}"; }
      When call export_and_check
      The output should equal ".eslintrc.json"
    End

    It "exports BRIK_QUALITY_LINT_FIX"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LINT_FIX:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_QUALITY_LINT_COMMAND"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LINT_COMMAND:-}"; }
      When call export_and_check
      The output should equal "npx eslint ."
    End

    It "exports BRIK_QUALITY_FORMAT_COMMAND"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_FORMAT_COMMAND:-}"; }
      When call export_and_check
      The output should equal "npx prettier --check ."
    End

    It "exports BRIK_QUALITY_TYPE_CHECK_TOOL"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_TYPE_CHECK_TOOL:-}"; }
      When call export_and_check
      The output should equal "tsc"
    End

    It "exports BRIK_QUALITY_TYPE_CHECK_COMMAND"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}"; }
      When call export_and_check
      The output should equal "npx tsc --noEmit"
    End
  End

  # =========================================================================
  # config.export_test_vars - coverage fields
  # =========================================================================
  Describe "config.export_test_vars coverage fields"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: jest
  coverage:
    threshold: 85
    report: coverage/cobertura.xml
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_TEST_COVERAGE_THRESHOLD"
      export_and_check() { config.export_test_vars; printf '%s' "${BRIK_TEST_COVERAGE_THRESHOLD:-}"; }
      When call export_and_check
      The output should equal "85"
    End

    It "exports BRIK_TEST_COVERAGE_REPORT"
      export_and_check() { config.export_test_vars; printf '%s' "${BRIK_TEST_COVERAGE_REPORT:-}"; }
      When call export_and_check
      The output should equal "coverage/cobertura.xml"
    End
  End

  # =========================================================================
  # config.export_package_vars
  # =========================================================================
  Describe "config.export_package_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
package:
  docker:
    image: registry.example.com/myapp
    dockerfile: Dockerfile.prod
    context: .
    platforms: linux/amd64,linux/arm64
    build_args: NODE_ENV=production
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_PACKAGE_DOCKER_IMAGE"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_IMAGE:-}"; }
      When call export_and_check
      The output should equal "registry.example.com/myapp"
    End

    It "exports BRIK_PACKAGE_DOCKER_DOCKERFILE"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_DOCKERFILE:-}"; }
      When call export_and_check
      The output should equal "Dockerfile.prod"
    End

    It "exports BRIK_PACKAGE_DOCKER_CONTEXT"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_CONTEXT:-}"; }
      When call export_and_check
      The output should equal "."
    End

    It "exports BRIK_PACKAGE_DOCKER_PLATFORMS"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_PLATFORMS:-}"; }
      When call export_and_check
      The output should equal "linux/amd64,linux/arm64"
    End

    It "exports BRIK_PACKAGE_DOCKER_BUILD_ARGS"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_BUILD_ARGS:-}"; }
      When call export_and_check
      The output should equal "NODE_ENV=production"
    End

    Describe "when package section absent"
      setup_empty() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_empty() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "succeeds with no exports"
        export_and_check() {
          unset BRIK_PACKAGE_DOCKER_IMAGE 2>/dev/null || true
          config.export_package_vars
          printf '%s' "${BRIK_PACKAGE_DOCKER_IMAGE:-empty}"
        }
        When call export_and_check
        The output should equal "empty"
      End
    End
  End

  # =========================================================================
  # config.export_deploy_vars
  # =========================================================================
  Describe "config.export_deploy_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: kubernetes
      namespace: staging-ns
      when: "branch == 'main'"
    production:
      target: kubernetes
      namespace: prod-ns
      manifest: k8s/production.yml
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_DEPLOY_ENVIRONMENTS"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS:-}"; }
      When call export_and_check
      The output should include "staging"
      The output should include "production"
    End

    It "exports BRIK_DEPLOY_STAGING_TARGET"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_TARGET:-}"; }
      When call export_and_check
      The output should equal "kubernetes"
    End

    It "exports BRIK_DEPLOY_STAGING_NAMESPACE"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_NAMESPACE:-}"; }
      When call export_and_check
      The output should equal "staging-ns"
    End

    It "exports BRIK_DEPLOY_PRODUCTION_MANIFEST"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_MANIFEST:-}"; }
      When call export_and_check
      The output should equal "k8s/production.yml"
    End

    Describe "when deploy section absent"
      setup_empty() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_empty() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "exports empty BRIK_DEPLOY_ENVIRONMENTS"
        export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS}"; }
        When call export_and_check
        The output should equal ""
      End
    End
  End

  # =========================================================================
  # config.export_notify_vars
  # =========================================================================
  Describe "config.export_notify_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
notify:
  slack:
    channel: "#builds"
    on: failure
  email:
    to: team@example.com
    on: always
  webhook:
    url: https://hooks.example.com/notify
    on: success
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_NOTIFY_SLACK_CHANNEL"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_SLACK_CHANNEL:-}"; }
      When call export_and_check
      The output should equal "#builds"
    End

    It "exports BRIK_NOTIFY_SLACK_ON"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_SLACK_ON:-}"; }
      When call export_and_check
      The output should equal "failure"
    End

    It "exports BRIK_NOTIFY_EMAIL_TO"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_EMAIL_TO:-}"; }
      When call export_and_check
      The output should equal "team@example.com"
    End

    It "exports BRIK_NOTIFY_WEBHOOK_URL"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_WEBHOOK_URL:-}"; }
      When call export_and_check
      The output should equal "https://hooks.example.com/notify"
    End
  End

  # =========================================================================
  # config.export_hooks_vars
  # =========================================================================
  Describe "config.export_hooks_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
hooks:
  pre_build: echo pre-build
  post_build: echo post-build
  pre_test: echo pre-test
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_HOOK_PRE_BUILD"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_PRE_BUILD:-}"; }
      When call export_and_check
      The output should equal "echo pre-build"
    End

    It "exports BRIK_HOOK_POST_BUILD"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_POST_BUILD:-}"; }
      When call export_and_check
      The output should equal "echo post-build"
    End

    It "exports BRIK_HOOK_PRE_TEST"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_PRE_TEST:-}"; }
      When call export_and_check
      The output should equal "echo pre-test"
    End
  End

  # =========================================================================
  # config.export_release_vars
  # =========================================================================
  Describe "config.export_release_vars"
    Describe "with explicit values"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
release:
  strategy: calver
  tag_prefix: release-
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_RELEASE_STRATEGY"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_STRATEGY:-}"; }
        When call export_and_check
        The output should equal "calver"
      End

      It "exports BRIK_RELEASE_TAG_PREFIX"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"; }
        When call export_and_check
        The output should equal "release-"
      End
    End

    Describe "defaults when release section absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "defaults BRIK_RELEASE_STRATEGY to semver"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_STRATEGY:-}"; }
        When call export_and_check
        The output should equal "semver"
      End

      It "defaults BRIK_RELEASE_TAG_PREFIX to v"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"; }
        When call export_and_check
        The output should equal "v"
      End
    End
  End

  # =========================================================================
  # config.export_all
  # =========================================================================
  Describe "config.export_all"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: full-app
  stack: node
  root: services/api
build:
  command: npm run build
test:
  framework: jest
quality:
  lint:
    enabled: true
security:
  severity_threshold: medium
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_PROJECT_NAME"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_PROJECT_NAME"
      }
      When call export_and_check
      The output should equal "full-app"
    End

    It "exports BRIK_PROJECT_ROOT"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_PROJECT_ROOT"
      }
      When call export_and_check
      The output should equal "services/api"
    End

    It "exports build vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_BUILD_COMMAND"
      }
      When call export_and_check
      The output should equal "npm run build"
    End

    It "exports test vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_TEST_FRAMEWORK"
      }
      When call export_and_check
      The output should equal "jest"
    End

    It "exports quality vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_LINT_ENABLED"
      }
      When call export_and_check
      The output should equal "true"
    End

    It "exports security vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_SECURITY_SEVERITY_THRESHOLD"
      }
      When call export_and_check
      The output should equal "medium"
    End

    It "returns 7 when config file does not exist"
      When call config.export_all "/nonexistent/brik.yml"
      The status should equal 7
      The error should be present
    End
  End

  # =========================================================================
  # brik.use config integration
  # =========================================================================
  Describe "brik.use config"
    Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"

    It "loads config module via brik.use"
      load_via_brik_use() {
        # Reset guards to allow re-load (loader guard + module guard)
        unset _BRIK_MODULE_CONFIG_LOADED _BRIK_CORE_CONFIG_LOADED 2>/dev/null || true
        brik.use config
        declare -f config.read >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call load_via_brik_use
      The output should equal "available"
    End
  End
End
