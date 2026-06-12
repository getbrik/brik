Describe "brik deploy E2E local (CD, digest-pinned)"
  # Exercises the full CD verb against a real workspace: resolve the version to
  # a digest in the accepted channel, enforce require_digest, and apply a k8s
  # manifest with the image pinned. The registry (curl, OCI distribution API)
  # and kubectl are mocked on PATH.
  #
  # The verb is exercised as the sourced cli.deploy.run function (not the
  # bin/brik child process) so kcov attributes the executed lines; one
  # dispatcher round-trip below keeps the bin/brik contract pinned.
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/cli/helpers.sh"
  Include "$BRIK_HOME/lib/cli/deploy.sh"
  # The dispatcher (bin/brik) owns this default; the sourced verb needs it.
  export BRIK_DEFAULT_CONFIG="brik.yml"

  DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  setup_repo() {
    # Pin the in-process (in-container) execution path: these examples
    # exercise the verb business logic, not the containerized engine.
    export BRIK_LOCAL_CONTAINER=1
    REPO="$(mktemp -d)"
    MOCKBIN="$(mktemp -d)"
    (
      cd "$REPO"
      git init -q -b main
      git config user.email "e2e@brik.dev"
      git config user.name "e2e"
      cat > brik.yml <<'YAML'
version: 1
project:
  name: cd-local
artifacts:
  channels:
    release:
      registry: registry.release/app
deploy:
  environments:
    staging:
      target: k8s
      manifest: k8s/deploy.yml
      namespace: staging
      accepts_channel: release
      gates:
        require_digest: true
YAML
      mkdir -p k8s
      cat > k8s/deploy.yml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:old
YAML
      git add -A >/dev/null
      git commit -q -m "baseline"
    )
    # kubectl mock prints the manifest it applies so the test can inspect it.
    printf '#!/bin/sh\n[ "$1" = "apply" ] && cat "$3"\nexit 0\n' > "${MOCKBIN}/kubectl"
    chmod +x "${MOCKBIN}/kubectl"
    # The channel's registry host must be declared in the referential.
    INFRA="$(mktemp -d)"
    mkdir -p "$INFRA/endpoints"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' > "$INFRA/referential.yml"
    cat > "$INFRA/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: https://registry.release
tls:
  trust: system
YAML
    cat > "$INFRA/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: keyless
transparency: rekor-public
YAML
    export BRIK_INFRA_DIR="$INFRA"
  }
  cleanup_repo() { rm -rf "$REPO" "$MOCKBIN" "$INFRA"; unset BRIK_INFRA_DIR; }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "resolves the digest and applies a manifest pinned to it"
    deploy_ok() {
      # curl returns a manifest response whose Docker-Content-Digest header
      # carries the immutable digest (headers go to stdout via -D -).
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment staging
    }
    When call deploy_ok
    The status should equal 0
    The output should include "@${DIGEST}"
    The stderr should include "resolved v1.2.3"
  End

  It "re-running the same deploy converges (idempotent re-entry, E1)"
    deploy_twice() {
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging >/dev/null || return $?
      # The lock must have been released and the second run must pin the
      # exact same digest: same inputs, same converged state.
      PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
    }
    When call deploy_twice
    The status should equal 0
    The output should include "@${DIGEST}"
    The stderr should include "resolved v1.2.3"
  End

  It "fails closed when require_digest is set and the digest cannot be resolved"
    deploy_failclosed() {
      # The registry has no such version: a 404 carries no digest header, so
      # resolution fails on every scheme and the gate must fail closed.
      printf '#!/bin/sh\nprintf "HTTP/1.1 404 Not Found\\r\\n\\r\\n"\nexit 0\n' > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v9.9.9 --environment staging
    }
    When call deploy_failclosed
    The status should equal 5
    The stderr should include "failing closed"
  End

  It "requires --version"
    When call cli.deploy.run --environment staging
    The status should equal 2
    The stderr should include "requires --version"
  End

  It "requires --environment"
    When call cli.deploy.run --version v1.2.3
    The status should equal 2
    The stderr should include "requires --environment"
  End

  It "rejects an unknown option"
    When call cli.deploy.run --version v1.2.3 --environment staging --bogus
    The status should equal 2
    The stderr should include "unknown option"
  End

  It "rejects an unknown environment"
    deploy_badenv() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment ghost
    }
    When call deploy_badenv
    The status should equal 7
    The stderr should include "unknown deploy environment"
  End

  Describe "attestation gate (require_attestation)"
    # Enable keyless attestation verification on the staging environment and
    # resolve the digest as usual; cosign is mocked to accept (emitting a
    # DSSE envelope wrapping a brik provenance predicate) or reject.
    enable_attestation() {
      yq -i '.deploy.environments.staging.gates.require_attestation = true
             | .deploy.environments.staging.gates.verify_identity = "https://ci/job/.*"
             | .deploy.environments.staging.gates.verify_issuer = "https://issuer.example"' \
        "$REPO/brik.yml"
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' \
        "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
    }

    # cosign mock: any verify call succeeds and prints the envelope whose
    # predicate carries <version>; verify_provenance then evaluates the
    # expectations against it for real.
    mock_cosign_envelope() {
      local version="$1"
      jq -cn --arg v "$version" '
        {
          buildDefinition: { externalParameters: { version: $v },
                             resolvedDependencies: [ { uri: "git+https://gitlab.example/team/app" } ] },
          runDetails: { builder: { id: "https://gitlab.example/-/brik/scanner",
                                   version: { brik: "0.6.0" } } }
        } as $pred
        | { _type: "https://in-toto.io/Statement/v1",
            predicateType: "https://slsa.dev/provenance/v1",
            predicate: $pred }
        | { payloadType: "application/vnd.in-toto+json",
            payload: (tojson | @base64) }' > "${MOCKBIN}/envelope.json"
      printf '#!/bin/sh\ncat "%s"\nexit 0\n' "${MOCKBIN}/envelope.json" > "${MOCKBIN}/cosign"
      chmod +x "${MOCKBIN}/cosign"
    }

    It "verifies the attestations and deploys when the expectations hold"
      deploy_att_ok() {
        enable_attestation
        mock_cosign_envelope "v1.2.3"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_att_ok
      The status should equal 0
      The stderr should include "attestation verified"
      The output should include "@${DIGEST}"
    End

    It "fails closed when the attestation does not verify"
      deploy_att_ko() {
        enable_attestation
        printf '#!/bin/sh\nexit 1\n' > "${MOCKBIN}/cosign"
        chmod +x "${MOCKBIN}/cosign"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_att_ko
      The status should equal 5
      The stderr should include "failing closed"
    End

    It "fails closed when the provenance is for another version (anti-substitution)"
      deploy_att_subst() {
        enable_attestation
        mock_cosign_envelope "v9.9.9"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_att_subst
      The status should equal 10
      The stderr should include "expectation"
    End

    It "fails closed when the builder is not the expected one"
      deploy_att_builder() {
        enable_attestation
        yq -i '.deploy.environments.staging.gates.expected_builder = "^https://trusted\\.example/-/brik/"' \
          "$REPO/brik.yml"
        mock_cosign_envelope "v1.2.3"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_att_builder
      The status should equal 10
      The stderr should include "expectation"
    End
  End

  Describe "eligibility gate (requires_eligibility)"
    # The grant lives in the PromotionJournal of the project's state-repo
    # (file:// fixture); the gate must find every configured event type for
    # the resolved digest and the target environment.
    setup_eligibility() {
      EL_REPO="$(mktemp -d)"
      (
        cd "$EL_REPO"
        git init -q -b main
        git config user.email "e2e@brik.dev"
        git config user.name "e2e"
        printf '{}\n' > seed.json
        git add -A >/dev/null
        git commit -q -m "seed"
      )
      EL_REPO_URL="file://$EL_REPO" yq -i \
        '.artifacts.evidence = {"repo": strenv(EL_REPO_URL), "branch": "main", "sign": false}
         | .deploy.environments.staging.gates.requires_eligibility = ["artifact_authorized_for"]' \
        "$REPO/brik.yml"
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' \
        "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
    }
    cleanup_eligibility() { rm -rf "$EL_REPO"; }
    Before 'setup_eligibility'
    After 'cleanup_eligibility'

    seed_grant() {
      local digest="$1" env="$2"
      mkdir -p "$EL_REPO/promotions/2026/06/11"
      jq -n --arg d "$digest" --arg e "$env" \
        '{schema: "brik.promotion-event/v1", type: "artifact_authorized_for",
          version: "v1.2.3", digest: $d, timestamp: "2026-06-11T14:30:00Z",
          environment: $e}' \
        > "$EL_REPO/promotions/2026/06/11/20260611T143000Z-aaaa0000aaaa0000.json"
      git -C "$EL_REPO" add -A >/dev/null
      git -C "$EL_REPO" commit -q -m "promotion: artifact_authorized_for v1.2.3"
    }

    It "refuses the deploy when the journal carries no grant for the environment"
      deploy_no_grant() {
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_no_grant
      The status should equal 10
      The stderr should include "refusing to deploy"
    End

    It "deploys once the digest is authorized for the environment"
      deploy_granted() {
        seed_grant "$DIGEST" staging
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_granted
      The status should equal 0
      The stderr should include "eligibility proven"
      The output should include "@${DIGEST}"
    End

    It "refuses a grant bound to another digest (anti-replay)"
      deploy_wrong_digest() {
        seed_grant "sha256:9999999999999999999999999999999999999999999999999999999999999999" staging
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_wrong_digest
      The status should equal 10
      The stderr should include "refusing to deploy"
    End

    It "fails closed when the journal is unreachable"
      deploy_unreachable() {
        yq -i '.artifacts.evidence.repo = "file:///does/not/exist/state.git"' "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_unreachable
      The status should equal 5
      The stderr should include "failing closed"
    End

    It "runs the gates in order: resolution, attestation, eligibility"
      deploy_ordered() {
        yq -i '.deploy.environments.staging.gates.require_attestation = true
               | .deploy.environments.staging.gates.verify_identity = "https://ci/.*"
               | .deploy.environments.staging.gates.verify_issuer = "https://issuer.example"' \
          "$REPO/brik.yml"
        jq -cn '{buildDefinition: {externalParameters: {version: "v1.2.3"},
                                   resolvedDependencies: [{uri: "git+https://x/y"}]},
                 runDetails: {builder: {id: "https://gitlab.example/-/brik/scanner"}}} as $pred
                | {payloadType: "application/vnd.in-toto+json",
                   payload: ({_type: "https://in-toto.io/Statement/v1", predicate: $pred} | tojson | @base64)}' \
          > "${MOCKBIN}/envelope.json"
        printf '#!/bin/sh\ncat "%s"\nexit 0\n' "${MOCKBIN}/envelope.json" > "${MOCKBIN}/cosign"
        chmod +x "${MOCKBIN}/cosign"
        seed_grant "$DIGEST" staging
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_ordered
      The status should equal 0
      The stderr should match pattern '*resolved v1.2.3*attestation verified*eligibility proven*'
      The output should include "@${DIGEST}"
    End
  End

  Describe "branch-protection arbitration (state_repo_protection)"
    # The protection check posture comes from the referential's Policy
    # document. The lab referential declares no GitHost, so the check itself
    # cannot be proven (rc 7): 'required' must refuse, 'warn' must continue,
    # 'off' must not even attempt it.
    setup_protection() {
      PROT_REPO="$(mktemp -d)"
      (
        cd "$PROT_REPO"
        git init -q -b main
        git config user.email "brik-ci@noreply"
        git config user.name "Brik CI"
        printf '{}\n' > event.json
        git add -A >/dev/null
        git commit -q -m "evidence: seed"
      )
      PROT_REPO_URL="file://$PROT_REPO" yq -i \
        '.artifacts.evidence = {"repo": strenv(PROT_REPO_URL), "branch": "main", "sign": false}' \
        "$REPO/brik.yml"
      # URL-aware curl mock: the same binary serves the policy fetch
      # (file:// -> cat) and the registry digest resolution (header blob).
      cat > "${MOCKBIN}/curl" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    file://*) cat "\${a#file://}"; exit 0 ;;
  esac
done
printf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: ${DIGEST}\\r\\n\\r\\n"
exit 0
EOF
      chmod +x "${MOCKBIN}/curl"
    }
    cleanup_protection() { rm -rf "$PROT_REPO"; }
    Before 'setup_protection'
    After 'cleanup_protection'

    write_protection_policy() {
      printf 'state_repo_protection: %s\n' "$1" > "$INFRA/brik-policy.yml"
      mkdir -p "$INFRA/policies"
      cat > "$INFRA/policies/org.yml" <<EOF
apiVersion: brik.dev/referential/v1
kind: Policy
name: org
url: file://$INFRA/brik-policy.yml
EOF
    }

    It "refuses to deploy when policy requires a protection that cannot be proven"
      deploy_required() {
        write_protection_policy required
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_required
      The status should equal 10
      The stderr should include "required by policy"
    End

    It "continues with a loud warning when the policy says warn"
      deploy_warn() {
        write_protection_policy warn
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_warn
      The status should equal 0
      The output should include "@${DIGEST}"
      The stderr should include "could not be verified"
    End

    It "skips the check entirely when the policy says off"
      deploy_off() {
        write_protection_policy off
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_off
      The status should equal 0
      The output should include "@${DIGEST}"
      The stderr should include "disabled by policy"
    End
  End

  Describe "evidence signature read-back (artifacts.evidence.sign)"
    # A project that declares signed evidence refuses to deploy when the
    # store's HEAD does not carry a verifiable ssh signature from the
    # referential's allowed_signers.
    setup_evidence() {
      EV_KEYDIR="$(mktemp -d)"
      ssh-keygen -t ed25519 -N "" -q -f "$EV_KEYDIR/id_ed25519"
      mkdir -p "$INFRA/trust"
      printf 'brik-ci@noreply namespaces="git" %s\n' "$(cat "$EV_KEYDIR/id_ed25519.pub")" \
        > "$INFRA/trust/allowed_signers"

      EV_REPO="$(mktemp -d)"
      (
        cd "$EV_REPO"
        git init -q -b main
        git config user.email "brik-ci@noreply"
        git config user.name "Brik CI"
        printf '{}\n' > event.json
        git add -A >/dev/null
      )

      EV_REPO_URL="file://$EV_REPO" yq -i \
        '.artifacts.evidence = {"repo": strenv(EV_REPO_URL), "branch": "main", "sign": true}' \
        "$REPO/brik.yml"
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
    }
    cleanup_evidence() { rm -rf "$EV_KEYDIR" "$EV_REPO"; }
    Before 'setup_evidence'
    After 'cleanup_evidence'

    sign_evidence_head() {
      git -C "$EV_REPO" -c gpg.format=ssh -c user.signingKey="$EV_KEYDIR/id_ed25519" \
        commit -q -S -m "evidence: seed"
    }

    It "verifies the signed evidence HEAD and deploys"
      deploy_ev_ok() {
        sign_evidence_head
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_ev_ok
      The status should equal 0
      The output should include "@${DIGEST}"
      The stderr should include "evidence store HEAD signature verified"
    End

    It "refuses to deploy when the evidence HEAD is unsigned (fail-closed)"
      deploy_ev_unsigned() {
        git -C "$EV_REPO" commit -q -m "evidence: seed"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_ev_unsigned
      The status should equal 5
      The stderr should include "refusing to deploy"
    End

    It "skips the verification when the project does not declare signed evidence"
      deploy_ev_unsigned_ok() {
        git -C "$EV_REPO" commit -q -m "evidence: seed"
        # Flip the declaration: unsigned evidence is a legal posture.
        yq -i '.artifacts.evidence.sign = false' "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_ev_unsigned_ok
      The status should equal 0
      The output should include "@${DIGEST}"
      The stderr should not include "evidence store HEAD"
    End
  End

  Describe "validation producer (validates_for)"
    # A successful deploy to an environment that declares validates_for emits
    # an artifact_validated_for event for the NEXT environment of the chain
    # (decision #2: the CD run is the producer, post-rollout). The event is
    # digest-bound and only appended when the run succeeded and the live
    # read-back does not contradict the pinned digest.
    setup_validation() {
      VAL_SEED="$(mktemp -d)"
      (
        cd "$VAL_SEED"
        git init -q -b main
        git config user.email "e2e@brik.dev"
        git config user.name "e2e"
        printf '{}\n' > seed.json
        git add -A >/dev/null
        git commit -q -m "seed"
      )
      VAL_DIR="$(mktemp -d)"
      VAL_REPO="${VAL_DIR}/state.git"
      git clone -q --bare "$VAL_SEED" "$VAL_REPO"
      VAL_REPO_URL="file://$VAL_REPO" yq -i \
        '.artifacts.evidence = {"repo": strenv(VAL_REPO_URL), "branch": "main", "sign": false}
         | .deploy.environments.staging.validates_for = "production"
         | .deploy.environments.production = {
             "target": "k8s", "manifest": "k8s/deploy.yml",
             "namespace": "production", "accepts_channel": "release"}' \
        "$REPO/brik.yml"
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' \
        "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
    }
    cleanup_validation() { rm -rf "$VAL_SEED" "$VAL_DIR"; }
    Before 'setup_validation'
    After 'cleanup_validation'

    journal_events() {
      local out
      out="$(mktemp -d)"
      git clone -q "file://$VAL_REPO" "$out" 2>/dev/null
      if [[ -d "$out/promotions" ]]; then
        find "$out/promotions" -name '*.json' -exec cat {} +
      else
        printf 'NO_EVENTS'
      fi
      rm -rf "$out"
    }

    It "journals artifact_validated_for the next environment after a green deploy"
      deploy_validates() {
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging >/dev/null || return $?
        journal_events
      }
      When call deploy_validates
      The status should equal 0
      The output should include '"type": "artifact_validated_for"'
      The output should include '"environment": "production"'
      The output should include "\"digest\": \"${DIGEST}\""
      The stderr should include "journaled artifact_validated_for"
    End

    It "feeds the next environment's eligibility gate (chain round-trip)"
      deploy_chain() {
        yq -i '.deploy.environments.production.gates.requires_eligibility = ["artifact_validated_for"]' \
          "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment production >/dev/null 2>/dev/null \
          && { echo "UNEXPECTED: production deployed without a validation"; return 1; }
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging >/dev/null || return $?
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment production
      }
      When call deploy_chain
      The status should equal 0
      The output should include "@${DIGEST}"
      The stderr should include "eligibility proven"
    End

    It "refuses a chain that names an undeclared environment, before deploying"
      deploy_ghost_next() {
        yq -i '.deploy.environments.staging.validates_for = "ghost"' "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_ghost_next
      The status should equal 7
      The stderr should include "validates_for"
      The output should not include "@${DIGEST}"
    End

    It "refuses a chain without a state-repo to journal into, before deploying"
      deploy_no_journal() {
        yq -i 'del(.artifacts.evidence)' "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_no_journal
      The status should equal 7
      The stderr should include "validates_for"
      The output should not include "@${DIGEST}"
    End

    It "refuses a chain on an environment without a channel to bind the digest"
      deploy_no_channel() {
        yq -i 'del(.deploy.environments.staging.accepts_channel)
               | del(.deploy.environments.staging.gates)' "$REPO/brik.yml"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_no_channel
      The status should equal 7
      The stderr should include "validates_for"
      The output should not include "@${DIGEST}"
    End

    It "does not journal when the deploy fails"
      deploy_red() {
        printf '#!/bin/sh\nexit 1\n' > "${MOCKBIN}/kubectl"
        chmod +x "${MOCKBIN}/kubectl"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging >/dev/null 2>/dev/null
        local rc=$?
        [ "$rc" -eq 0 ] && return 1
        journal_events
      }
      When call deploy_red
      The status should equal 0
      The output should include "NO_EVENTS"
    End

    It "withholds the validation when the live read-back contradicts the pinned digest"
      deploy_contradicted() {
        # kubectl: apply succeeds, but the live deployment runs ANOTHER digest.
        cat > "${MOCKBIN}/kubectl" <<'EOF'
#!/bin/sh
[ "$1" = "apply" ] && cat "$3" && exit 0
[ "$1" = "get" ] && printf 'registry.release/app@sha256:9999999999999999999999999999999999999999999999999999999999999999' && exit 0
exit 0
EOF
        chmod +x "${MOCKBIN}/kubectl"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging >/dev/null
        local rc=$?
        printf 'RC=%s ' "$rc"
        journal_events
      }
      When call deploy_contradicted
      The status should equal 0
      The output should include "RC=10"
      The output should include "NO_EVENTS"
      The stderr should include "read-back"
    End

    It "dry-run journals nothing"
      deploy_dryrun() {
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging --dry-run >/dev/null 2>/dev/null || return $?
        journal_events
      }
      When call deploy_dryrun
      The status should equal 0
      The output should include "NO_EVENTS"
    End
  End
End
