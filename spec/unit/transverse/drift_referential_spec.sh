#!/usr/bin/env bash
# drift_referential_spec.sh - Liveness guard (P-F) for the referential schemas.
#
# Extends the schema-runtime drift detector beyond brik.yml config to the
# infrastructure-referential schemas (schemas/referential/v1/*.json), whose
# leaves are consumed via infra.* (jq reads of the endpoint/credential doc),
# not via config.get / BRIK_* exports.
#
# Three new helpers (in _drift_helpers.sh):
#   drift.walk_annotated <schema>          - emit "path<TAB>info<TAB>dep" per leaf
#   drift.is_informational <schema> <path> - 0 if leaf (or an ancestor) is x-informational
#   drift.is_deprecated <schema> <path>    - 0 if leaf (or an ancestor) is deprecated
#   drift.has_infra_consumer <path> <dir>  - 0 if a jq/yq read of the leaf exists in lib/

Describe "drift.walk_annotated"
  setup() {
    FIXTURE="$(mktemp)"
    cat > "$FIXTURE" <<'JSON'
{
  "type": "object",
  "properties": {
    "a": { "type": "string" },
    "b": { "type": "string", "x-informational": true },
    "c": {
      "type": "object",
      "deprecated": true,
      "properties": { "x": { "type": "string" } }
    }
  }
}
JSON
  }
  cleanup() { rm -f "$FIXTURE"; }
  Before 'setup'
  After 'cleanup'

  emit() {
    . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
    drift.walk_annotated "$FIXTURE"
  }

  It "marks a plain leaf as live (no flags)"
    When call emit
    The line 1 of output should equal ".a	-	-"
  End

  It "marks an x-informational leaf"
    When call emit
    The line 2 of output should equal ".b	info	-"
  End

  It "propagates a deprecated marker from an ancestor object to its leaf"
    When call emit
    The line 3 of output should equal ".c.x	-	dep"
  End
End

Describe "drift.is_informational / drift.is_deprecated"
  setup() {
    FIXTURE="$(mktemp)"
    cat > "$FIXTURE" <<'JSON'
{
  "type": "object",
  "properties": {
    "a": { "type": "string" },
    "b": { "type": "string", "x-informational": true },
    "c": { "type": "object", "deprecated": true, "properties": { "x": { "type": "string" } } }
  }
}
JSON
  }
  cleanup() { rm -f "$FIXTURE"; }
  Before 'setup'
  After 'cleanup'

  is_info() { . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"; drift.is_informational "$FIXTURE" "$1"; }
  is_dep()  { . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"; drift.is_deprecated "$FIXTURE" "$1"; }

  It "is_informational is true for an x-informational leaf"
    When call is_info ".b"
    The status should equal 0
  End
  It "is_informational is false for a plain leaf"
    When call is_info ".a"
    The status should equal 1
  End
  It "is_deprecated is true for a leaf under a deprecated object"
    When call is_dep ".c.x"
    The status should equal 0
  End
  It "is_deprecated is false for a plain leaf"
    When call is_dep ".a"
    The status should equal 1
  End
End

Describe "drift.has_infra_consumer"
  setup_sandbox() { SANDBOX="$(mktemp -d)"; }
  cleanup_sandbox() { rm -rf "$SANDBOX"; }
  Before 'setup_sandbox'
  After 'cleanup_sandbox'

  It "finds a jq read of the leaf field"
    has_it() {
      . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
      printf 'uri="$(printf %%s "$doc" | jq -r '\''.kms_uri'\'')"\n' > "${SANDBOX}/x.sh"
      drift.has_infra_consumer ".kms_uri" "$SANDBOX"
    }
    When call has_it
    The status should equal 0
  End

  It "matches by the last segment of a nested path"
    has_nested() {
      . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
      printf 'trust="$(jq -r .trust <<<"$ep")"\n' > "${SANDBOX}/x.sh"
      drift.has_infra_consumer ".tls.trust" "$SANDBOX"
    }
    When call has_nested
    The status should equal 0
  End

  It "reports drift when no read exists (e.g. dead field)"
    has_none() {
      . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
      printf 'echo nothing\n' > "${SANDBOX}/x.sh"
      drift.has_infra_consumer ".referrers" "$SANDBOX"
    }
    When call has_none
    The status should equal 1
  End
End

Describe "drift.pending_leaves / drift.is_pending"
  setup() {
    FIXTURE="$(mktemp)"
    cat > "$FIXTURE" <<'JSON'
{
  "type": "object",
  "properties": {
    "a": { "type": "string" },
    "p": { "type": "string", "x-pending": "wired in T9" },
    "obj": {
      "type": "object",
      "x-pending": "object wired in T9",
      "properties": { "leaf": { "type": "string" } }
    }
  }
}
JSON
  }
  cleanup() { rm -f "$FIXTURE"; }
  Before 'setup'
  After 'cleanup'

  pend() { . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"; drift.pending_leaves "$FIXTURE"; }
  is_pend() { . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"; drift.is_pending "$FIXTURE" "$1"; }

  It "emits a leaf carrying x-pending"
    When call pend
    The output should include ".p"
  End
  It "propagates x-pending from an ancestor object to its leaf"
    When call pend
    The output should include ".obj.leaf"
  End
  It "does not emit a plain leaf"
    When call pend
    The output should not include ".a"
  End
  It "is_pending is true for an x-pending leaf"
    When call is_pend ".p"
    The status should equal 0
  End
  It "is_pending is false for a plain leaf"
    When call is_pend ".a"
    The status should equal 1
  End
End

Describe "referential schema-runtime drift detector"
  It "every referential leaf has an infra consumer, or is x-informational / deprecated"
    check_all() {
      . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
      local lib_dir="${BRIK_HOME}/lib"
      local schema name path info dep missing=0 missing_list=""
      for schema in "${BRIK_HOME}"/schemas/referential/v1/*.json; do
        name="${schema##*/}"; name="${name%.schema.json}"
        while IFS="$(printf '\t')" read -r path info dep; do
          [[ -z "$path" ]] && continue
          # Exempt leaves marked intentionally not-consumed (info), on their way
          # out (deprecated), or schema-ahead-of-runtime (x-pending, tracked).
          [[ "$info" == "info" || "$dep" == "dep" ]] && continue
          drift.is_pending "$schema" "$path" && continue
          if ! drift.has_infra_consumer "$path" "$lib_dir"; then
            missing=$((missing + 1))
            missing_list="${missing_list}  MISSING: ${name}${path}\n"
          fi
        done < <(drift.walk_annotated "$schema")
      done
      if [[ "$missing" -gt 0 ]]; then
        printf 'Referential drift (%d leaf(s) without consumer/marker):\n' "$missing"
        printf '%b' "$missing_list"
        return 1
      fi
      return 0
    }
    When call check_all
    The status should equal 0
  End

  It "x-pending leaves stay few and are listed (schema-ahead-of-runtime backlog)"
    list_pending() {
      . "${BRIK_HOME}/spec/unit/transverse/_drift_helpers.sh"
      local schema name total=0
      for schema in "${BRIK_HOME}"/schemas/referential/v1/*.json; do
        name="${schema##*/}"; name="${name%.schema.json}"
        while IFS= read -r path; do
          [[ -z "$path" ]] && continue
          total=$((total + 1))
          printf '  PENDING: %s%s\n' "$name" "$path"
        done < <(drift.pending_leaves "$schema")
      done
      if [[ "$total" -gt 5 ]]; then
        printf 'Too many x-pending referential leaves (%d, limit 5). Wire them.\n' "$total"
        return 1
      fi
      return 0
    }
    When call list_pending
    The status should equal 0
    The output should include "PENDING: k8starget.kubeconfig"
  End
End
