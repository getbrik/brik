#shellcheck shell=bash
# Contract for lib/transverse/evidence.sh -- the BuildEvidence store.
#
# Evidence is a file-per-digest JSON committed to the state-repo via
# transverse.state_repo.*. The store functions are stubbed against a fake
# state-repo so the contract checks the document shape and the append path,
# not real git.

Describe "transverse.evidence"
  BRIK_HOME="$(cd "${SHELLSPEC_PROJECT_ROOT}" && pwd)"
  export BRIK_HOME
  Include "${BRIK_HOME}/lib/pipeline/error.sh"

  brik.use() { :; }
  log.info()  { :; }
  log.warn()  { :; }
  log.error() { printf 'ERROR: %s\n' "$*" >&2; }

  Include "${BRIK_HOME}/lib/transverse/evidence.sh"

  DIGEST="sha256:3333333333333333333333333333333333333333333333333333333333333333"

  Describe "evidence.relpath"
    It "encodes the image digest in the path (OCI referrer tag form)"
      When call evidence.relpath "v1.2.3" "$DIGEST"
      The output should equal "evidence/v1.2.3/sha256-3333333333333333333333333333333333333333333333333333333333333333.json"
    End
  End

  Describe "evidence.build"
    doc() {
      evidence.build \
        --version v1.2.3 --digest "$DIGEST" --commit abc123 --run-id run-9 \
        --platform gitlab \
        --sbom-ref sbom.cyclonedx.json --provenance-ref provenance.slsa.json \
        --version-ref refs/tags/v1.2.3 --env-config-ref refs/heads/main
    }

    It "produces a valid JSON document carrying the subject digest"
      validate() { doc | jq -e '.digest' >/dev/null; }
      When call validate
      The status should be success
    End

    It "carries digest, version, commit, ci_run_id and evidence refs"
      When call doc
      The output should include '"digest": "sha256:3333333333333333333333333333333333333333333333333333333333333333"'
      The output should include '"version": "v1.2.3"'
      The output should include '"commit": "abc123"'
      The output should include '"ci_run_id": "run-9"'
      The output should include "sbom.cyclonedx.json"
      The output should include "provenance.slsa.json"
      The output should include "refs/tags/v1.2.3"
    End
  End

  Describe "evidence.publish"
    # Capture the relpath the evidence is appended at and the commit message.
    setup_pub() {
      # append runs in a pipe (subshell) in the module, so record its path to a
      # file; commit is direct, so a variable is fine.
      APPEND_REC="$(mktemp)"
      COMMIT_MSG=""
      SIGNED="no"
      transverse.state_repo.clone()  { return 0; }
      transverse.state_repo.append() { printf '%s' "$2" >"$APPEND_REC"; cat >/dev/null; }
      transverse.state_repo.commit() {
        COMMIT_MSG="$2"
        case "$*" in *--sign*) SIGNED="yes" ;; esac
        return 0
      }
      transverse.state_repo.push()   { return 0; }
    }
    cleanup_pub() { rm -f "$APPEND_REC"; }
    BeforeEach setup_pub
    AfterEach cleanup_pub

    It "appends the evidence at the digest-addressed path and signs the commit"
      pub() {
        evidence.publish --repo https://git/state.git --version v1.2.3 --digest "$DIGEST" --sign \
          <<<"$(printf '{"digest":"%s"}' "$DIGEST")"
        printf '%s|%s|%s' "$(cat "$APPEND_REC")" "$SIGNED" "$COMMIT_MSG"
      }
      When call pub
      The status should be success
      The output should include "evidence/v1.2.3/sha256-3333333333333333333333333333333333333333333333333333333333333333.json"
      The output should include "|yes|"
    End

    It "dry-run does not append"
      pub() {
        evidence.publish --repo https://git/state.git --version v1.2.3 --digest "$DIGEST" --dry-run \
          <<<"$(printf '{"digest":"%s"}' "$DIGEST")"
        printf '%s' "$(cat "$APPEND_REC")"
      }
      When call pub
      The status should be success
      The output should equal ""
    End

    It "converges as a no-op when the same commit already evidenced the digest (re-run)"
      pub_rerun() {
        # A reproducible build re-runs CI on the same commit and produces the
        # SAME digest: the store already vouches for it. Only ci_run_id
        # differs between the two documents.
        log.info() { printf 'INFO: %s\n' "$*" >&2; }
        transverse.state_repo.clone() {
          mkdir -p "$2/evidence/v1.2.3"
          printf '{"digest":"%s","commit":"abc123","ci_run_id":"run-1"}' "$DIGEST" \
            > "$2/evidence/v1.2.3/sha256-${DIGEST#sha256:}.json"
          return 0
        }
        evidence.publish --repo https://git/state.git --version v1.2.3 --digest "$DIGEST" \
          <<<"$(printf '{"digest":"%s","commit":"abc123","ci_run_id":"run-2"}' "$DIGEST")" || return $?
        printf 'APPEND=[%s]' "$(cat "$APPEND_REC")"
      }
      When call pub_rerun
      The status should be success
      The output should equal "APPEND=[]"
      The stderr should include "converged"
    End

    It "fails closed when the digest is already evidenced by another commit"
      pub_conflict() {
        transverse.state_repo.clone() {
          mkdir -p "$2/evidence/v1.2.3"
          printf '{"digest":"%s","commit":"somebody-else","ci_run_id":"run-1"}' "$DIGEST" \
            > "$2/evidence/v1.2.3/sha256-${DIGEST#sha256:}.json"
          return 0
        }
        evidence.publish --repo https://git/state.git --version v1.2.3 --digest "$DIGEST" \
          <<<"$(printf '{"digest":"%s","commit":"abc123","ci_run_id":"run-2"}' "$DIGEST")"
      }
      When call pub_conflict
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "conflict"
    End
  End
End
