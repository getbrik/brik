Describe "config.sh - validate and publish"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.validate_coherence
  # =========================================================================
  Describe "config.validate_coherence"

    Describe "node + jest in devDependencies"
      setup_coherent_jest() {
        COHERENT_WS="$(mktemp -d)"
        printf '{"name":"test","devDependencies":{"jest":"^29.0.0"}}\n' > "${COHERENT_WS}/package.json"
        COHERENT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: jest\n' > "$COHERENT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$COHERENT_WS"
        export BRIK_CONFIG_FILE="$COHERENT_CONFIG"
      }
      cleanup_coherent_jest() {
        rm -rf "$COHERENT_WS" "$COHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_coherent_jest'
      After 'cleanup_coherent_jest'

      It "passes when jest is in devDependencies"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "node + jest not in deps + custom test script"
      setup_incoherent_jest() {
        INCOHERENT_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"node test/index.test.js"}}\n' > "${INCOHERENT_WS}/package.json"
        INCOHERENT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$INCOHERENT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$INCOHERENT_WS"
        export BRIK_CONFIG_FILE="$INCOHERENT_CONFIG"
      }
      cleanup_incoherent_jest() {
        rm -rf "$INCOHERENT_WS" "$INCOHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_incoherent_jest'
      After 'cleanup_incoherent_jest'

      It "fails with exit 7 and descriptive error"
        When call config.validate_coherence
        The status should equal 7
        The error should include "config mismatch"
        The error should include "jest is not in package.json"
        The error should include "stack default"
      End
    End

    Describe "node + framework=npm"
      setup_npm_framework() {
        NPM_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"node test/index.test.js"}}\n' > "${NPM_WS}/package.json"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="npm"
        export BRIK_WORKSPACE="$NPM_WS"
      }
      cleanup_npm_framework() {
        rm -rf "$NPM_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_npm_framework'
      After 'cleanup_npm_framework'

      It "passes (no jest coherence check needed)"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "non-node stack"
      setup_python_stack() {
        PYTHON_WS="$(mktemp -d)"
        export BRIK_BUILD_STACK="python"
        export BRIK_TEST_FRAMEWORK="pytest"
        export BRIK_WORKSPACE="$PYTHON_WS"
      }
      cleanup_python_stack() {
        rm -rf "$PYTHON_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_python_stack'
      After 'cleanup_python_stack'

      It "passes (skip node-specific checks)"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "node + jest + no package.json"
      setup_no_pkgjson() {
        NO_PKGJSON_WS="$(mktemp -d)"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$NO_PKGJSON_WS"
      }
      cleanup_no_pkgjson() {
        rm -rf "$NO_PKGJSON_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_no_pkgjson'
      After 'cleanup_no_pkgjson'

      It "passes when package.json is absent"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "node + jest + malformed package.json"
      setup_malformed() {
        MALFORMED_WS="$(mktemp -d)"
        printf 'not valid json{{{' > "${MALFORMED_WS}/package.json"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$MALFORMED_WS"
      }
      cleanup_malformed() {
        rm -rf "$MALFORMED_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_malformed'
      After 'cleanup_malformed'

      It "warns and passes on malformed package.json"
        When call config.validate_coherence
        The status should be success
        The error should include "skipping coherence validation"
      End
    End

    Describe "node + jest mismatch from brik.yml"
      setup_explicit_jest() {
        EXPLICIT_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"mocha"}}\n' > "${EXPLICIT_WS}/package.json"
        EXPLICIT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: jest\n' > "$EXPLICIT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$EXPLICIT_WS"
        export BRIK_CONFIG_FILE="$EXPLICIT_CONFIG"
      }
      cleanup_explicit_jest() {
        rm -rf "$EXPLICIT_WS" "$EXPLICIT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_explicit_jest'
      After 'cleanup_explicit_jest'

      It "reports brik.yml as the source"
        When call config.validate_coherence
        The status should equal 7
        The error should include "brik.yml"
      End
    End
  End

  # =========================================================================
  # config.export_publish_vars
  # =========================================================================
  Describe "config.export_publish_vars"
    Describe "with npm publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  npm:
    registry: https://npm.example.com
    tag: beta
    access: public
    token_var: NPM_TOKEN
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_NPM_REGISTRY"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NPM_REGISTRY:-}"; }
        When call export_and_check
        The output should equal "https://npm.example.com"
      End

      It "exports BRIK_PUBLISH_NPM_TAG"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NPM_TAG:-}"; }
        When call export_and_check
        The output should equal "beta"
      End

      It "exports BRIK_PUBLISH_NPM_ACCESS"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NPM_ACCESS:-}"; }
        When call export_and_check
        The output should equal "public"
      End

      It "exports BRIK_PUBLISH_NPM_TOKEN_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NPM_TOKEN_VAR:-}"; }
        When call export_and_check
        The output should equal "NPM_TOKEN"
      End
    End

    Describe "with docker publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  docker:
    image: ghcr.io/org/app
    registry: ghcr.io
    tags:
      - v1.0.0
      - latest
    username_var: DOCKER_USER
    password_var: DOCKER_PASS
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_DOCKER_IMAGE"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_DOCKER_IMAGE:-}"; }
        When call export_and_check
        The output should equal "ghcr.io/org/app"
      End

      It "exports BRIK_PUBLISH_DOCKER_REGISTRY"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_DOCKER_REGISTRY:-}"; }
        When call export_and_check
        The output should equal "ghcr.io"
      End

      It "exports BRIK_PUBLISH_DOCKER_TAGS as comma-separated"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_DOCKER_TAGS:-}"; }
        When call export_and_check
        The output should equal "v1.0.0,latest"
      End

      It "exports BRIK_PUBLISH_DOCKER_USERNAME_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_DOCKER_USERNAME_VAR:-}"; }
        When call export_and_check
        The output should equal "DOCKER_USER"
      End

      It "exports BRIK_PUBLISH_DOCKER_PASSWORD_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_DOCKER_PASSWORD_VAR:-}"; }
        When call export_and_check
        The output should equal "DOCKER_PASS"
      End
    End

    Describe "with maven publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  maven:
    repository: https://maven.example.com/releases
    username_var: MAVEN_USER
    password_var: MAVEN_PASS
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_MAVEN_REPOSITORY"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_MAVEN_REPOSITORY:-}"; }
        When call export_and_check
        The output should equal "https://maven.example.com/releases"
      End

      It "exports BRIK_PUBLISH_MAVEN_USERNAME_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_MAVEN_USERNAME_VAR:-}"; }
        When call export_and_check
        The output should equal "MAVEN_USER"
      End
    End

    Describe "with pypi publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  pypi:
    repository: https://test.pypi.org/legacy/
    token_var: PYPI_TOKEN
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_PYPI_REPOSITORY"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_PYPI_REPOSITORY:-}"; }
        When call export_and_check
        The output should equal "https://test.pypi.org/legacy/"
      End

      It "exports BRIK_PUBLISH_PYPI_TOKEN_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_PYPI_TOKEN_VAR:-}"; }
        When call export_and_check
        The output should equal "PYPI_TOKEN"
      End
    End

    Describe "with cargo publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  cargo:
    registry: my-registry
    token_var: CARGO_TOKEN
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_CARGO_REGISTRY"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_CARGO_REGISTRY:-}"; }
        When call export_and_check
        The output should equal "my-registry"
      End

      It "exports BRIK_PUBLISH_CARGO_TOKEN_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_CARGO_TOKEN_VAR:-}"; }
        When call export_and_check
        The output should equal "CARGO_TOKEN"
      End
    End

    Describe "with nuget publish config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
publish:
  nuget:
    source: https://api.nuget.org/v3/index.json
    api_key_var: NUGET_KEY
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_PUBLISH_NUGET_SOURCE"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NUGET_SOURCE:-}"; }
        When call export_and_check
        The output should equal "https://api.nuget.org/v3/index.json"
      End

      It "exports BRIK_PUBLISH_NUGET_API_KEY_VAR"
        export_and_check() { config.export_publish_vars; printf '%s' "${BRIK_PUBLISH_NUGET_API_KEY_VAR:-}"; }
        When call export_and_check
        The output should equal "NUGET_KEY"
      End
    End

    Describe "with no publish section"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "succeeds with no exports"
        export_and_check() {
          config.export_publish_vars
          printf '%s' "${BRIK_PUBLISH_NPM_REGISTRY:-}${BRIK_PUBLISH_DOCKER_IMAGE:-}"
        }
        When call export_and_check
        The output should equal ""
      End
    End
  End

  # =========================================================================
  # config.export_release_vars with changelog
  # =========================================================================
  Describe "config.export_release_vars with changelog"
    Describe "with explicit changelog values"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
release:
  strategy: semver
  tag_prefix: v
  changelog:
    enabled: false
    format: keep-a-changelog
    file: CHANGES.md
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_RELEASE_CHANGELOG_ENABLED"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_ENABLED:-}"; }
        When call export_and_check
        The output should equal "false"
      End

      It "exports BRIK_RELEASE_CHANGELOG_FORMAT"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_FORMAT:-}"; }
        When call export_and_check
        The output should equal "keep-a-changelog"
      End

      It "exports BRIK_RELEASE_CHANGELOG_FILE"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_FILE:-}"; }
        When call export_and_check
        The output should equal "CHANGES.md"
      End
    End

    Describe "defaults when changelog section absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "defaults BRIK_RELEASE_CHANGELOG_ENABLED to true"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_ENABLED:-}"; }
        When call export_and_check
        The output should equal "true"
      End

      It "defaults BRIK_RELEASE_CHANGELOG_FORMAT to conventional"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_FORMAT:-}"; }
        When call export_and_check
        The output should equal "conventional"
      End

      It "defaults BRIK_RELEASE_CHANGELOG_FILE to CHANGELOG.md"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_CHANGELOG_FILE:-}"; }
        When call export_and_check
        The output should equal "CHANGELOG.md"
      End
    End
  End
End
