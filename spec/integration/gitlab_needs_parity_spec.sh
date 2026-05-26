#shellcheck shell=bash
# Anti-drift contract: the needs[] declared in each GitLab job template
# stays in sync with the manifest's dependency declarations (Lot 5 of
# chantier 20260526_pipeline-invariants-centralization.md).
#
# Catches the case where a developer edits a manifest's placement.after
# or consumes[] without updating the corresponding templates/jobs/<id>.yml.
# GitLab parses needs: at YAML-parse time so it must stay static; this
# spec is what guarantees it stays correct.
#
# What we verify (subset relation, not strict equality):
#   - Every id in placement.after MUST appear in needs[]
#   - Every stage that provides what this stage consumes MUST appear
#     in needs[] (the consumer can't read a product without depending
#     on the producer)
#   - plan and init MUST be in every gateable stage's needs[]
#     (foundational convention: plan computes the gate, init posts the
#     dotenv with stack image + BRIK_IMG_*)
#
# What we don't verify here:
#   - artifacts: true/false flag per dependency (operational decision,
#     not derivable from the manifest alone -- promote depends on
#     container-scan but with artifacts: false because it doesn't
#     need the SARIF files copied)
#   - optional: true/false flag (depends on the upstream stage's
#     gate.mode in plan context, which varies per build)

Describe "gitlab needs[] parity with manifest declarations"
  MANIFESTS_DIR="${BRIK_HOME}/lib/registry/manifests/stages"
  GITLAB_JOBS_DIR="${BRIK_HOME}/shared-libs/gitlab/templates/jobs"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  product_provider_map() {
    local f id products p
    for f in "$MANIFESTS_DIR"/*.yml; do
      id="$(yq -r '.metadata.id' "$f")"
      products="$(yq -r '.spec.provides // [] | .[]' "$f" 2>/dev/null)"
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        printf '%s=%s\n' "$p" "$id"
      done <<<"$products"
    done
  }

  expected_needs_for() {
    local stage_id="$1"
    local manifest="${MANIFESTS_DIR}/${stage_id}.yml"
    [[ -f "$manifest" ]] || return 1

    {
      printf 'plan\n'
      if [[ "$stage_id" != "init" ]]; then
        printf 'init\n'
      fi

      yq -r '.spec.placement.after // [] | .[]' "$manifest" 2>/dev/null

      local product_map
      product_map="$(product_provider_map)"
      local consumed p provider
      consumed="$(yq -r '.spec.consumes // [] | .[]' "$manifest" 2>/dev/null)"
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        provider="$(echo "$product_map" | grep -m1 "^${p}=" | cut -d= -f2)"
        [[ -n "$provider" ]] && printf '%s\n' "$provider"
      done <<<"$consumed"
    } | LC_ALL=C sort -u
  }

  actual_needs_for() {
    local stage_id="$1"
    local yaml="${GITLAB_JOBS_DIR}/${stage_id}.yml"
    [[ -f "$yaml" ]] || return 1
    # mikefarah yq v4 DSL: no `// empty`. Use `.[]?.job` so missing
    # needs[] does not error out (notify-like cases).
    yq -r ".\"brik-${stage_id}\".needs[].job" "$yaml" 2>/dev/null \
      | sed 's/^brik-//' | LC_ALL=C sort -u
  }

  missing_needs_for() {
    local stage_id="$1"
    comm -23 <(expected_needs_for "$stage_id") <(actual_needs_for "$stage_id")
  }

  Describe "every gateable stage YAML satisfies the manifest's dependency contract"
    Parameters
      "release"
      "build"
      "lint"
      "sast"
      "scan"
      "test"
      "package"
      "container-scan"
      "promote"
      "deploy"
    End

    It "$1.yml needs[] covers placement.after + consumes-providers"
      Skip if "yq not installed" yq_missing
      When call missing_needs_for "$1"
      The output should equal ""
    End
  End

  Describe "init.yml depends on plan only"
    It "init has plan in needs[]"
      Skip if "yq not installed" yq_missing
      check_init_needs() {
        actual_needs_for "init" | grep -qx "plan"
      }
      When call check_init_needs
      The status should be success
    End
  End

  Describe "notify.yml depends on every other stage (optional fan-in)"
    It "notify lists plan + init in needs[]"
      Skip if "yq not installed" yq_missing
      check_notify_foundational() {
        local needs
        needs="$(actual_needs_for "notify")"
        echo "$needs" | grep -qx "plan" && echo "$needs" | grep -qx "init"
      }
      When call check_notify_foundational
      The status should be success
    End
  End
End
