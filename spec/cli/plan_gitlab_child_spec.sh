Describe "brik plan --format gitlab-child (D.5c)"

  setup_dir() {
    TMPDIR_RUN="$(mktemp -d)"
    PLAN_JSON="$TMPDIR_RUN/plan.json"
    PLAN_YML="$TMPDIR_RUN/plan.yml"
  }
  cleanup_dir() {
    rm -rf "$TMPDIR_RUN"
  }
  Before 'setup_dir'
  After 'cleanup_dir'

  Describe "snapshot, no opt-in flags"
    It "writes plan.json AND a child pipeline YAML next to it"
      When run script "$BRIK_BIN" plan \
        --workspace /tmp \
        --mode safe \
        --format gitlab-child \
        --out "$PLAN_JSON"
      The status should equal 0
      The path "$PLAN_JSON" should be file
      The path "$PLAN_YML" should be file
      The output should include "gitlab-child:"
    End

    It "includes the parent template"
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call grep -qE "include:" "$PLAN_YML"
      The status should equal 0
    End

    It "overrides each skipped non-notify job with rules:when:never"
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call grep -qE "^brik-(release|package|container-scan|deploy):$" "$PLAN_YML"
      The status should equal 0
    End

    It "does not include a rules:when:never block under brik-notify"
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      detect_notify_skip() {
        awk '
          /^brik-notify:/ { flag = 1; next }
          flag && /rules:/ { print "skip-found"; exit }
          flag && /^[^[:space:]]/ { flag = 0 }
        ' "$PLAN_YML"
      }
      When call detect_notify_skip
      The output should equal ""
    End

    It "lists run-stage siblings (not skipped ones) in notify needs"
      # Notify's needs in the child contains only the plan's run
      # decisions; the cross-pipeline parent reference was dropped
      # because GitLab >=19.x returns missing_dependency_failure when
      # the cross-pipeline artifact lookup is attempted from a
      # trigger:include:artifact child (briklab smoke L.1).
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call grep -qE "job: brik-init" "$PLAN_YML"
      The status should equal 0
    End

    It "embeds the plan fingerprint in a header comment"
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call grep -qE "fingerprint: [0-9a-f]{64}" "$PLAN_YML"
      The status should equal 0
    End

    It "produces valid YAML (yq parses it)"
      "$BRIK_BIN" plan --workspace /tmp --mode safe --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call yq eval . "$PLAN_YML"
      The status should equal 0
      The output should be present
    End
  End

  Describe "release context"
    It "keeps notify as a runnable job (it is the report aggregator)"
      BRIK_COMMIT_TAG=v1.2.3 "$BRIK_BIN" plan \
        --workspace /tmp --mode safe --with-deploy \
        --format gitlab-child --out "$PLAN_JSON" >/dev/null
      When call grep -qE "^brik-notify:$" "$PLAN_YML"
      The status should equal 0
    End
  End

  Describe "unknown format"
    It "rejects --format=xml"
      When run script "$BRIK_BIN" plan --workspace /tmp --format xml --out "$PLAN_JSON"
      The status should equal 2
      The stderr should include "not a known format"
    End
  End
End
