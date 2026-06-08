Describe "brik deploy identity (F5) - same (version, environment) => same actions"
  # Behavioural identity (design S7.5 invariant 5): re-deploying the same
  # version to the same environment resolves the same digest, injects the same
  # pinned ref, and produces a byte-identical deploy plan. Registry (curl) and
  # kubectl are mocked on PATH; runs are --dry-run (no cluster needed).

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
  name: cd-identity
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
    printf '#!/bin/sh\n[ "$1" = "apply" ] && cat "$3"\nexit 0\n' > "${MOCKBIN}/kubectl"
    chmod +x "${MOCKBIN}/kubectl"
    printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' "$DIGEST" > "${MOCKBIN}/curl"
    chmod +x "${MOCKBIN}/curl"
  }
  cleanup_repo() { rm -rf "$REPO" "$MOCKBIN"; }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "yields an identical pinned ref and deploy plan across two runs"
    run_twice() {
      cd "$REPO"
      local L1 L2 OUT1 OUT2 R1 R2
      L1="$(mktemp -d)"; L2="$(mktemp -d)"
      OUT1="$(BRIK_LOG_DIR="$L1" PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment staging --dry-run 2>/dev/null)"
      OUT2="$(BRIK_LOG_DIR="$L2" PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.2.3 --environment staging --dry-run 2>/dev/null)"

      R1="$(printf '%s' "$OUT1" | grep -o '@sha256:[0-9a-f]\{64\}' | head -1)"
      R2="$(printf '%s' "$OUT2" | grep -o '@sha256:[0-9a-f]\{64\}' | head -1)"
      [ -n "$R1" ] && [ "$R1" = "$R2" ] && printf 'ref_match=%s\n' "$R1"

      if diff -q "$L1/plan.json" "$L2/plan.json" >/dev/null 2>&1; then
        printf 'plan_match=yes\n'
      else
        printf 'plan_match=no\n'
      fi
      rm -rf "$L1" "$L2"
    }
    When call run_twice
    The output should include "ref_match=@${DIGEST}"
    The output should include "plan_match=yes"
  End
End
