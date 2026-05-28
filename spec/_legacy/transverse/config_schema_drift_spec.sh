#!/usr/bin/env bash
# config_schema_drift_spec.sh - Schema-runtime drift detector
#
# Asserts that every leaf in schemas/config/v1/brik.schema.json has a
# runtime consumer in lib/ (config.get call or BRIK_* export), or is
# listed in the allowlist as a known inert field.

Describe "drift.walk_leaves"
  setup() {
    FIXTURE_SCHEMA="$(mktemp)"
    cat > "$FIXTURE_SCHEMA" <<'JSON'
{
  "type": "object",
  "properties": {
    "a": { "type": "string" },
    "b": { "$ref": "#/$defs/B" },
    "c": {
      "type": "object",
      "additionalProperties": { "$ref": "#/$defs/C" }
    }
  },
  "$defs": {
    "B": { "type": "object", "properties": { "x": { "type": "string" } } },
    "C": { "type": "string" }
  }
}
JSON
  }
  cleanup() { rm -f "$FIXTURE_SCHEMA"; }
  Before 'setup'
  After 'cleanup'

  walk_fixture() {
    # shellcheck source=/dev/null
    . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
    drift.walk_leaves "$FIXTURE_SCHEMA"
  }

  It "emits .a for a plain string property"
    When call walk_fixture
    The output should include ".a"
  End

  It "emits .b.x by resolving the B ref"
    When call walk_fixture
    The output should include ".b.x"
  End

  It "emits .c.<key> for additionalProperties with a string schema"
    When call walk_fixture
    The output should include ".c.<key>"
  End

  It "emits exactly three leaves for the fixture schema"
    count_leaves() {
      . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
      drift.walk_leaves "$FIXTURE_SCHEMA" | wc -l | tr -d ' '
    }
    When call count_leaves
    The output should equal "3"
  End
End

Describe "drift.derive_envvar"
  setup_helpers() {
    # shellcheck source=/dev/null
    . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
  }
  Before 'setup_helpers'

  It "derives BRIK_PROJECT_STACK from .project.stack"
    When call drift.derive_envvar ".project.stack"
    The output should equal "BRIK_PROJECT_STACK"
  End

  It "derives BRIK_DEPLOY_[A-Z][A-Z0-9_]*_TARGET from .deploy.environments.<key>.target"
    When call drift.derive_envvar ".deploy.environments.<key>.target"
    The output should equal "BRIK_DEPLOY_[A-Z][A-Z0-9_]*_TARGET"
  End

  It "derives BRIK_PUBLISH_DOCKER_TAGS from .publish.docker.tags"
    When call drift.derive_envvar ".publish.docker.tags"
    The output should equal "BRIK_PUBLISH_DOCKER_TAGS"
  End

  It "returns BRIK_LINT_ENABLED for .quality.lint.enabled (documented exception)"
    When call drift.derive_envvar ".quality.lint.enabled"
    The output should equal "BRIK_LINT_ENABLED"
  End

  It "returns BRIK_HOOK_PRE_BUILD for .hooks.pre_build (documented exception)"
    When call drift.derive_envvar ".hooks.pre_build"
    The output should equal "BRIK_HOOK_PRE_BUILD"
  End
End

Describe "drift.has_consumer"
  setup_sandbox() {
    SANDBOX_LIB="$(mktemp -d)"
  }
  cleanup_sandbox() { rm -rf "$SANDBOX_LIB"; }
  Before 'setup_sandbox'
  After 'cleanup_sandbox'

  It "finds a path-based consumer (config.get literal)"
    test_path_consumer() {
      . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
      printf "val=\"\$(config.get '.x.y' '')\"\n" > "${SANDBOX_LIB}/test.sh"
      drift.has_consumer ".x.y" "$SANDBOX_LIB"
    }
    When call test_path_consumer
    The status should equal 0
  End

  It "finds an env-var consumer (BRIK_ export)"
    test_envvar_consumer() {
      . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
      printf 'export BRIK_X_Y="value"\n' > "${SANDBOX_LIB}/test.sh"
      drift.has_consumer ".x.y" "$SANDBOX_LIB"
    }
    When call test_envvar_consumer
    The status should equal 0
  End

  It "reports drift when lib dir is empty"
    test_no_consumer() {
      . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
      drift.has_consumer ".x.y" "$SANDBOX_LIB"
    }
    When call test_no_consumer
    The status should equal 1
  End
End

Describe "schema-runtime drift detector"
  It "every schema leaf has a runtime consumer in lib/ or is allowlisted"
    check_all_leaves() {
      . "${BRIK_HOME}/spec/_legacy/transverse/_drift_helpers.sh"
      local allowlist="${BRIK_HOME}/spec/_legacy/transverse/_drift_allowlist.txt"
      local lib_dir="${BRIK_HOME}/lib"
      local missing=0
      local missing_list=""

      while IFS= read -r leaf; do
        [[ -z "$leaf" ]] && continue

        # Check allowlist (skip comment and blank lines; strip inline comments)
        local allowed=0
        while IFS= read -r allow_line; do
          [[ "$allow_line" =~ ^[[:space:]]*# ]] && continue
          [[ -z "$allow_line" ]] && continue
          local allow_path
          allow_path="$(printf '%s' "$allow_line" | sed 's/[[:space:]]*#.*//' | tr -d '[:space:]')"
          if [[ "$allow_path" == "$leaf" ]]; then
            allowed=1
            break
          fi
        done < "$allowlist"

        [[ "$allowed" -eq 1 ]] && continue

        if ! drift.has_consumer "$leaf" "$lib_dir"; then
          missing=$((missing + 1))
          missing_list="${missing_list}  MISSING: ${leaf}\n"
        fi
      done < <(drift.walk_leaves "$BRIK_SCHEMA")

      if [[ "$missing" -gt 0 ]]; then
        printf 'Schema-runtime drift detected (%d leaf(s) without consumer):\n' "$missing"
        printf '%b' "$missing_list"
        return 1
      fi
      return 0
    }
    When call check_all_leaves
    The status should equal 0
  End

  It "allowlist stays small (at most 10 entries)"
    check_allowlist_size() {
      local allowlist="${BRIK_HOME}/spec/_legacy/transverse/_drift_allowlist.txt"
      local count
      count="$(grep -cv '^[[:space:]]*#\|^[[:space:]]*$' "$allowlist" 2>/dev/null || printf '0')"
      if [[ "$count" -gt 10 ]]; then
        printf 'Allowlist has %d entries (limit 10). Improve the detector.\n' "$count"
        return 1
      fi
      return 0
    }
    When call check_allowlist_size
    The status should equal 0
  End
End
