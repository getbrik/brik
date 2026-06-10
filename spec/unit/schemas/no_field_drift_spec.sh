#shellcheck shell=bash
# Anti-drift contract: the plan.json v1 schema may only declare fields
# from a documented allowlist, and never matches the banned patterns
# (Lot 5 of chantier 20260526_pipeline-invariants-centralization.md).
#
# Operationalises the two design rules acted as global memory:
#   feedback-schema-field-justification: every field added to a schema
#     must justify itself; if derivable from other fields with no
#     information loss, do not add it.
#   feedback-document-single-ontology: a document must not mix two
#     ontologies (invariant vs platform-specific, static vs dynamic).
#
# Fails when:
#   - a field is added that is NOT in the allowlist (forces an explicit
#     decision: extend the allowlist with a justification comment, OR
#     remove the field)
#   - a field matches a banned pattern (^platform_, platform_job_name,
#     display_name in this schema, ...)

Describe "no field drift in schemas/plan/v1/plan.schema.json"
  SCHEMA="${BRIK_HOME}/schemas/plan/v1/plan.schema.json"

  jq_missing() { ! command -v jq >/dev/null 2>&1; }

  # Recursively collect every property NAME declared anywhere in the
  # schema. Walks every parent path that ends with "properties" and
  # picks its child names. Sorted unique.
  schema_field_names() {
    jq -r '[paths | select(length >= 2 and .[-2] == "properties") | .[-1]]
           | unique | .[]' "$SCHEMA"
  }

  # Documented allowlist. Every entry has an implicit justification:
  #   - inherent to the plan contract (schemaVersion, context, mode,
  #     workspace, release, changes, stages, dag, fingerprint, ...)
  #   - Lot 1+3 additions (runner_class)
  #   - legacy fields kept for v1 stability (brikVersion: predates the
  #     justification rule; will be reconsidered on a future v2 bump)
  #   - CD plan-kind (additive): planType + the deploy block
  #     {version, environment, channel, digest} -- an explicit deploy is
  #     parameterized by (version, environment); channel/digest record what
  #     was resolved. None is derivable from the others. See
  #     20260606_cicd-decoupling-implementation-plan.md (T3).
  #   - infra {fingerprint}: pins the infrastructure referential the plan
  #     was derived against (the referential is mandatory; reproducibility
  #     extends to the declared environment). Not derivable: the referential
  #     lives outside the workspace, so neither HEAD nor brik.yml covers it.
  allowlist() {
    cat <<'EOF'
brikVersion
changes
context
dag
decision
edges
files
fingerprint
from
from_ref
function
gate
id
is_candidate
matched_globs
mode
opt_in_flag
contexts
profile
reason
release
runner_class
schemaVersion
source
stages
to
to_ref
version
workspace
planType
deploy
environment
channel
digest
infra
EOF
  }

  Describe "every field in the schema is in the documented allowlist"
    It "no unjustified field has been added to plan.schema.json"
      Skip if "jq not installed" jq_missing
      forbidden() {
        comm -23 \
          <(schema_field_names | LC_ALL=C sort -u) \
          <(allowlist | LC_ALL=C sort -u)
      }
      When call forbidden
      The output should equal ""
    End
  End

  Describe "no field matches a banned pattern"
    # display_name is banned at the plan.schema level: the human label
    # belongs to the manifests (metadata.displayName), not the plan
    # (which carries decisions, not UI hints). The brik registry stages
    # CLI exposes it for Jenkins consumption, also without persisting
    # it in plan.json.
    Parameters
      "^platform_"
      "^display_name$"
      "platform_job_name"
    End

    It "no field matches '$1'"
      Skip if "jq not installed" jq_missing
      matching() {
        schema_field_names | grep -E "$1" || true
      }
      When call matching "$1"
      The output should equal ""
    End
  End
End
