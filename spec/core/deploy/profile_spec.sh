Describe "deploy/profile.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/error.sh"
  Include "$BRIK_CORE_LIB/deploy/profile.sh"

  # =========================================================================
  # deploy.profile.resolve
  # =========================================================================
  Describe "deploy.profile.resolve"
    It "resolves trunk-based profile path"
      When call deploy.profile.resolve "trunk-based"
      The status should be success
      The output should include "trunk-based.yml"
    End

    It "resolves git-flow profile path"
      When call deploy.profile.resolve "git-flow"
      The status should be success
      The output should include "git-flow.yml"
    End

    It "resolves github-flow profile path"
      When call deploy.profile.resolve "github-flow"
      The status should be success
      The output should include "github-flow.yml"
    End

    It "returns 2 for unknown workflow"
      When call deploy.profile.resolve "unknown-workflow"
      The status should equal 2
      The stderr should include "unknown workflow"
    End

    It "returns 2 for empty workflow"
      When call deploy.profile.resolve ""
      The status should equal 2
      The stderr should include "workflow is required"
    End

    It "profile path exists on disk for trunk-based"
      check_exists() {
        local path
        path="$(deploy.profile.resolve "trunk-based")" || return 1
        [[ -f "$path" ]] && echo "exists" || echo "missing"
      }
      When call check_exists
      The output should equal "exists"
    End

    It "profile path exists on disk for git-flow"
      check_exists() {
        local path
        path="$(deploy.profile.resolve "git-flow")" || return 1
        [[ -f "$path" ]] && echo "exists" || echo "missing"
      }
      When call check_exists
      The output should equal "exists"
    End

    It "profile path exists on disk for github-flow"
      check_exists() {
        local path
        path="$(deploy.profile.resolve "github-flow")" || return 1
        [[ -f "$path" ]] && echo "exists" || echo "missing"
      }
      When call check_exists
      The output should equal "exists"
    End
  End

  # =========================================================================
  # deploy.profile.merge
  # =========================================================================
  Describe "deploy.profile.merge"
    setup_yq() {
      # These tests require yq to be available
      command -v yq >/dev/null 2>&1 || skip "yq not available"
    }
    Before 'setup_yq'

    Describe "with a minimal brik.yml (no deploy section)"
      setup_minimal() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
      }
      cleanup_minimal() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_minimal'
      After 'cleanup_minimal'

      It "returns a temp file path"
        check_merge() {
          local out
          out="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          [[ -n "$out" ]] && echo "has_path" || echo "empty_path"
        }
        When call check_merge
        The output should equal "has_path"
      End

      It "merged file is a valid YAML file"
        check_merge_valid() {
          local merged
          merged="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          [[ -f "$merged" ]] && echo "exists" || echo "missing"
        }
        When call check_merge_valid
        The output should equal "exists"
      End

      It "trunk-based merge contains staging environment"
        check_staging() {
          local merged
          merged="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          yq '.deploy.environments.staging' "$merged" 2>/dev/null
        }
        When call check_staging
        The output should not equal "null"
      End

      It "trunk-based merge contains production environment"
        check_production() {
          local merged
          merged="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          yq '.deploy.environments.production' "$merged" 2>/dev/null
        }
        When call check_production
        The output should not equal "null"
      End

      It "git-flow merge contains dev environment"
        check_dev() {
          local merged
          merged="$(deploy.profile.merge "git-flow" "$TEMP_CONFIG")" || return 1
          yq '.deploy.environments.dev' "$merged" 2>/dev/null
        }
        When call check_dev
        The output should not equal "null"
      End

      It "github-flow merge contains preview environment"
        check_preview() {
          local merged
          merged="$(deploy.profile.merge "github-flow" "$TEMP_CONFIG")" || return 1
          yq '.deploy.environments.preview' "$merged" 2>/dev/null
        }
        When call check_preview
        The output should not equal "null"
      End
    End

    Describe "user overrides take precedence over profile defaults"
      setup_override() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
deploy:
  workflow: trunk-based
  environments:
    staging:
      namespace: my-custom-namespace
YAML
      }
      cleanup_override() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_override'
      After 'cleanup_override'

      It "user namespace overrides profile default"
        check_namespace() {
          local merged
          merged="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          yq '.deploy.environments.staging.namespace' "$merged" 2>/dev/null
        }
        When call check_namespace
        The output should equal "my-custom-namespace"
      End

      It "profile when condition is preserved when user does not override"
        check_when() {
          local merged
          merged="$(deploy.profile.merge "trunk-based" "$TEMP_CONFIG")" || return 1
          local when
          when="$(yq '.deploy.environments.staging.when' "$merged" 2>/dev/null)"
          [[ -n "$when" && "$when" != "null" ]] && echo "has_when" || echo "no_when"
        }
        When call check_when
        The output should equal "has_when"
      End
    End

    Describe "error handling"
      It "returns 2 for empty workflow"
        When call deploy.profile.merge "" "/some/path.yml"
        The status should equal 2
        The stderr should include "workflow is required"
      End

      It "returns 6 for non-existent brik.yml"
        When call deploy.profile.merge "trunk-based" "/nonexistent/brik.yml"
        The status should equal 6
        The stderr should include "not found"
      End

      It "returns 2 for unknown workflow"
        check_unknown() {
          local tmp
          tmp="$(mktemp)"
          printf 'version: 1\n' > "$tmp"
          deploy.profile.merge "bad-workflow" "$tmp"
          local rc=$?
          rm -f "$tmp"
          return $rc
        }
        When call check_unknown
        The status should equal 2
        The stderr should include "unknown workflow"
      End
    End
  End

  # =========================================================================
  # guard pattern
  # =========================================================================
  Describe "double-sourcing guard"
    It "is callable after double include"
      double_include() {
        # shellcheck source=/dev/null
        . "$BRIK_CORE_LIB/deploy/profile.sh"
        declare -f deploy.profile.resolve >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
