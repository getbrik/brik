Describe "planning/plan_writer.sh"
  Include "$BRIK_HOME/lib/planning/plan_writer.sh"

  Describe "plan_writer.write (end-to-end)"
    It "emits a JSON object with the expected top-level keys"
      When call plan_writer.write -- --workspace /tmp --mode safe
      The status should be success
      The output should include '"schemaVersion": "v1"'
      The output should include '"context": "snapshot"'
      The output should include '"mode": "safe"'
      The output should include '"fingerprint"'
      The output should include '"dag"'
      The output should include '"release"'
    End

    It "stamps a release block with profile, version and is_candidate"
      release_block() {
        local out
        out="$(plan_writer.write -- --workspace /tmp --mode safe)"
        local profile version candidate
        profile="$(jq -r '.release.profile' <<<"$out")"
        version="$(jq -r '.release.version' <<<"$out")"
        candidate="$(jq -r '.release.is_candidate' <<<"$out")"
        printf '%s|%s|%s' "$profile" "$version" "$candidate"
      }
      # /tmp has no brik.yml and no git tags, so the planner falls back
      # to the safe defaults (profile=none, version=0.0.0). BRIK_COMMIT_TAG
      # is not exported in the test env, so is_candidate=false.
      When call release_block
      The status should be success
      The output should equal "none|0.0.0|false"
    End

    It "is reproducible: two consecutive runs produce byte-identical bytes"
      a=$(plan_writer.write -- --workspace /tmp --mode safe)
      b=$(plan_writer.write -- --workspace /tmp --mode safe)
      When call test "$a" = "$b"
      The status should be success
    End

    It "writes to --out when given"
      out=$(mktemp -d)/plan.json
      When call plan_writer.write --out "$out" -- --workspace /tmp --mode safe
      The status should be success
      The path "$out" should be file
      rm -rf "$(dirname "$out")"
    End

    It "produces a sorted dag.edges array"
      first_edge=$(plan_writer.write -- --workspace /tmp --mode safe \
                   | jq -r '.dag.edges[0] | "\(.from) \(.to)"')
      When call test "$first_edge" = "build lint"
      The status should be success
    End

    It "computes a 64-hex sha256 fingerprint"
      fp=$(plan_writer.write -- --workspace /tmp --mode safe | jq -r '.fingerprint')
      When call test "${#fp}" -eq 64
      The status should be success
    End

    It "passes JSON Schema validation via jv when available"
      out=$(mktemp)
      plan_writer.write -- --workspace /tmp --mode safe > "$out"
      if ! command -v jv >/dev/null 2>&1; then
        Skip "jv not installed"
      fi
      When call jv "$BRIK_HOME/schemas/plan/v1/plan.schema.json" "$out"
      The status should be success
      The output should include "ok"
      rm -f "$out"
    End
  End

  Describe "plan_writer.from_stream"
    It "fails when no stage records are present"
      When call plan_writer.from_stream
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "no stage records"
    End
  End
End
