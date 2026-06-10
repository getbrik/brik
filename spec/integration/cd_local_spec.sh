Describe "brik deploy E2E local (CD, digest-pinned)"
  # Exercises the full CD verb against a real workspace: resolve the version to
  # a digest in the accepted channel, enforce require_digest, and apply a k8s
  # manifest with the image pinned. The registry (curl, OCI distribution API)
  # and kubectl are mocked on PATH.

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
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v9.9.9 --environment staging
    }
    When call deploy_failclosed
    The status should equal 5
    The stderr should include "failing closed"
  End

  It "rejects an unknown environment"
    deploy_badenv() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment ghost
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
        PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment staging
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
        PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment staging
      }
      When call deploy_prov_ko
      The status should equal 5
      The stderr should include "failing closed"
    End
  End
End
