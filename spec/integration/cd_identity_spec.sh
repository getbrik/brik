Describe "brik deploy identity (F5) - same (version, environment) => same actions"
  # Behavioural identity (design S7.5 invariant 5): re-deploying the same
  # version to the same environment resolves the same digest, injects the same
  # pinned ref, and produces a byte-identical deploy plan. Registry (curl) and
  # kubectl are mocked on PATH; runs are --dry-run (no cluster needed).

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

  It "containerized local path: two runs spawn an identical deploy container"
    # F5 extended to the containerized engine: same (version, environment)
    # on a bare host => the deploy-class container is launched with the same
    # arguments, the run volume name (timestamp-pid) being the only delta.
    run_containerized_twice() {
      cd "$REPO"
      # The mock consumes piped stdin like the real engine (tar seed stream);
      # otherwise the seed pipe dies on SIGPIPE under bin/brik's pipefail.
      printf '#!/bin/sh\necho "docker $*" >> "${DOCKER_LOG}"\ncase "$*" in *" -i "*) cat > /dev/null 2>&1 || true ;; esac\nexit 0\n' > "${MOCKBIN}/docker"
      chmod +x "${MOCKBIN}/docker"
      local D1 D2
      D1="$(mktemp)"; D2="$(mktemp)"
      BRIK_LOCAL_CONTAINER= DOCKER_LOG="$D1" PATH="${MOCKBIN}:$PATH" \
        "$BRIK_BIN" deploy --version v1.2.3 --environment staging --dry-run >/dev/null 2>&1
      BRIK_LOCAL_CONTAINER= DOCKER_LOG="$D2" PATH="${MOCKBIN}:$PATH" \
        "$BRIK_BIN" deploy --version v1.2.3 --environment staging --dry-run >/dev/null 2>&1
      local A1 A2
      A1="$(grep "bin/brik deploy" "$D1" | sed 's/brik-run-[0-9]*-[0-9]*/brik-run-X/g')"
      A2="$(grep "bin/brik deploy" "$D2" | sed 's/brik-run-[0-9]*-[0-9]*/brik-run-X/g')"
      rm -f "$D1" "$D2"
      if [ -n "$A1" ] && [ "$A1" = "$A2" ]; then
        printf 'container_match=yes\n'
      else
        printf 'container_match=no\nA1=%s\nA2=%s\n' "$A1" "$A2"
      fi
    }
    When call run_containerized_twice
    The output should equal "container_match=yes"
  End
End
