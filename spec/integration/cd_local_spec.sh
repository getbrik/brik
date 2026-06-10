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

  Describe "provenance gate (require_provenance)"
    # Enable keyless provenance verification on the staging environment and
    # resolve the digest as usual; cosign is mocked to accept or reject.
    enable_provenance() {
      yq -i '.deploy.environments.staging.gates.require_provenance = true
             | .deploy.environments.staging.gates.verify_identity = "https://ci/job/.*"
             | .deploy.environments.staging.gates.verify_issuer = "https://issuer.example"' \
        "$REPO/brik.yml"
      printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' \
        "$DIGEST" > "${MOCKBIN}/curl"
      chmod +x "${MOCKBIN}/curl"
    }

    It "verifies the attestation and deploys when it verifies"
      deploy_prov_ok() {
        enable_provenance
        printf '#!/bin/sh\nexit 0\n' > "${MOCKBIN}/cosign"
        chmod +x "${MOCKBIN}/cosign"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_prov_ok
      The status should equal 0
      The stderr should include "provenance verified"
      The output should include "@${DIGEST}"
    End

    It "fails closed when the attestation does not verify"
      deploy_prov_ko() {
        enable_provenance
        printf '#!/bin/sh\nexit 1\n' > "${MOCKBIN}/cosign"
        chmod +x "${MOCKBIN}/cosign"
        cd "$REPO"
        PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging
      }
      When call deploy_prov_ko
      The status should equal 5
      The stderr should include "failing closed"
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
End
