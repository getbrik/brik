Describe "config.sh - stage_enabled and stack_default"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.stage_enabled
  # =========================================================================
  Describe "config.stage_enabled"
    Describe "always-enabled stages"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "returns 0 for init"
        When call config.stage_enabled "init"
        The status should be success
      End

      It "returns 0 for build"
        When call config.stage_enabled "build"
        The status should be success
      End

      It "returns 0 for test"
        When call config.stage_enabled "test"
        The status should be success
      End

      It "returns 0 for notify"
        When call config.stage_enabled "notify"
        The status should be success
      End
    End

    Describe "lint stage"
      Describe "when quality.lint.enabled is true"
        setup_quality_on() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nquality:\n  lint:\n    enabled: true\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_quality_on'
        After 'cleanup'

        It "is enabled when quality.lint.enabled is true"
          When call config.stage_enabled "lint"
          The status should be success
        End
      End

      Describe "when quality section is absent"
        setup_no_quality() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_quality'
        After 'cleanup'

        It "is enabled by default when quality section is absent"
          When call config.stage_enabled "lint"
          The status should be success
        End
      End

      Describe "when quality.lint.enabled is false"
        setup_quality_off() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nquality:\n  lint:\n    enabled: false\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_quality_off'
        After 'cleanup'

        It "is disabled when quality.lint.enabled is false"
          When call config.stage_enabled "lint"
          The status should equal 1
        End
      End
    End

    Describe "sast and scan stages"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup'

      It "returns 0 for sast (always enabled)"
        When call config.stage_enabled "sast"
        The status should be success
      End

      It "returns 0 for scan (always enabled)"
        When call config.stage_enabled "scan"
        The status should be success
      End
    End

    Describe "container_scan stage"
      Describe "when container image is configured"
        setup_container() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nsecurity:\n  container:\n    image: myapp:latest\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_container'
        After 'cleanup'

        It "is enabled when security.container.image is set"
          When call config.stage_enabled "container_scan"
          The status should be success
        End
      End

      Describe "when container image is not configured"
        setup_no_container() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_container'
        After 'cleanup'

        It "is disabled when security.container.image is not set"
          When call config.stage_enabled "container_scan"
          The status should equal 1
        End
      End
    End

    Describe "verify stage"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup'

      It "returns 0 for verify (always enabled)"
        When call config.stage_enabled "verify"
        The status should be success
      End
    End

    Describe "release stage"
      Describe "when release.strategy is set"
        setup_release() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nrelease:\n  strategy: semver\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_release'
        After 'cleanup'

        It "is enabled when release.strategy is set"
          When call config.stage_enabled "release"
          The status should be success
        End
      End

      Describe "when release section is absent"
        setup_no_release() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_release'
        After 'cleanup'

        It "is disabled when release section is absent"
          When call config.stage_enabled "release"
          The status should equal 1
        End
      End
    End

    Describe "package stage"
      Describe "when package.docker.image is set"
        setup_package() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\npackage:\n  docker:\n    image: my-registry/my-app\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_package'
        After 'cleanup'

        It "is enabled when package.docker.image is set"
          When call config.stage_enabled "package"
          The status should be success
        End
      End

      Describe "when package section is absent"
        setup_no_package() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_package'
        After 'cleanup'

        It "is disabled when package section is absent"
          When call config.stage_enabled "package"
          The status should equal 1
        End
      End
    End

    Describe "deploy stage"
      Describe "when deploy.environments has entries"
        setup_deploy() {
          TEMP_CONFIG="$(mktemp)"
          cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      when: "branch == 'main'"
YAML
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_deploy'
        After 'cleanup'

        It "is enabled when deploy.environments has entries"
          When call config.stage_enabled "deploy"
          The status should be success
        End
      End

      Describe "when deploy section is absent"
        setup_no_deploy() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_deploy'
        After 'cleanup'

        It "is disabled when deploy section is absent"
          When call config.stage_enabled "deploy"
          The status should equal 1
        End
      End
    End

    Describe "unknown stages"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup'

      It "returns 1 for unknown stages"
        When call config.stage_enabled "foobar"
        The status should equal 1
      End
    End
  End

  # =========================================================================
  # config.stack_default
  # =========================================================================
  Describe "config.stack_default"
    It "returns node build_command"
      When call config.stack_default "node" "build_command"
      The output should equal ""
    End

    It "returns node format_tool"
      When call config.stack_default "node" "format_tool"
      The output should equal "prettier"
    End

    It "returns java build_command"
      When call config.stack_default "java" "build_command"
      The output should equal ""
    End

    It "returns java format_tool"
      When call config.stack_default "java" "format_tool"
      The output should equal "google-java-format"
    End

    It "returns python test_framework"
      When call config.stack_default "python" "test_framework"
      The output should equal "pytest"
    End

    It "returns python format_tool"
      When call config.stack_default "python" "format_tool"
      The output should equal "ruff-format"
    End

    It "returns dotnet build_command"
      When call config.stack_default "dotnet" "build_command"
      The output should equal ""
    End

    It "returns dotnet format_tool"
      When call config.stack_default "dotnet" "format_tool"
      The output should equal "dotnet-format"
    End

    It "returns rust lint_tool"
      When call config.stack_default "rust" "lint_tool"
      The output should equal "clippy"
    End

    It "returns rust format_tool"
      When call config.stack_default "rust" "format_tool"
      The output should equal "rustfmt"
    End

    It "returns 1 for unknown stack"
      When call config.stack_default "unknown" "build_command"
      The status should equal 1
    End

    It "returns 1 for unknown setting on valid stack"
      When call config.stack_default "node" "nonexistent_setting"
      The status should equal 1
    End
  End
End
