Describe "brik deploy E2E local (CD, digest-pinned)"
  # Exercises the full CD verb against a real workspace: resolve the version to
  # a digest in the accepted channel, enforce require_digest, and apply a k8s
  # manifest with the image pinned. crane and kubectl are mocked on PATH.

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
  }
  cleanup_repo() { rm -rf "$REPO" "$MOCKBIN"; }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "resolves the digest and applies a manifest pinned to it"
    deploy_ok() {
      printf '#!/bin/sh\necho "%s"\n' "$DIGEST" > "${MOCKBIN}/crane"
      chmod +x "${MOCKBIN}/crane"
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
      # crane fails: no digest can be resolved for the version.
      printf '#!/bin/sh\nexit 1\n' > "${MOCKBIN}/crane"
      chmod +x "${MOCKBIN}/crane"
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
End
