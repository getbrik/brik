Describe "brik status E2E local (three layers + drift)"
  # Exercises the status verb against a real workspace: a deploy seeds the
  # DeploymentJournal in a bare state-repo, then the verb reports the three
  # layers (journal, desired, live) and the drift verdicts. The registry
  # (curl) and kubectl are mocked on PATH; the live layer comes from the
  # kubectl read-back of the k8s target.
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/cli/helpers.sh"
  Include "$BRIK_HOME/lib/cli/deploy.sh"
  Include "$BRIK_HOME/lib/cli/status.sh"
  export BRIK_DEFAULT_CONFIG="brik.yml"

  DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  OTHER_DIGEST="sha256:9999999999999999999999999999999999999999999999999999999999999999"

  setup_status() {
    # Pin the in-process (in-container) execution path.
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
  name: cd-status
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
    # The state-repo is bare: the deploy journals its deployed event there.
    ST_SEED="$(mktemp -d)"
    (
      cd "$ST_SEED"
      git init -q -b main
      git config user.email "e2e@brik.dev"
      git config user.name "e2e"
      printf '{}\n' > seed.json
      git add -A >/dev/null
      git commit -q -m "seed"
    )
    ST_DIR="$(mktemp -d)"
    ST_REPO="${ST_DIR}/state.git"
    git clone -q --bare "$ST_SEED" "$ST_REPO"
    ST_REPO_URL="file://$ST_REPO" yq -i \
      '.artifacts.evidence = {"repo": strenv(ST_REPO_URL), "branch": "main", "sign": false}' \
      "$REPO/brik.yml"
    git -C "$REPO" commit -aqm "evidence wired"

    # curl: digest resolution; kubectl: apply prints the manifest, get reads
    # back the pinned ref (the converged live state).
    printf '#!/bin/sh\nprintf "HTTP/1.1 200 OK\\r\\nDocker-Content-Digest: %s\\r\\n\\r\\n"\nexit 0\n' \
      "$DIGEST" > "${MOCKBIN}/curl"
    cat > "${MOCKBIN}/kubectl" <<EOF
#!/bin/sh
[ "\$1" = "apply" ] && cat "\$3" && exit 0
[ "\$1" = "get" ] && printf 'registry.release/app@${DIGEST}' && exit 0
exit 0
EOF
    chmod +x "${MOCKBIN}/curl" "${MOCKBIN}/kubectl"

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
  cleanup_status() {
    rm -rf "$REPO" "$MOCKBIN" "$INFRA" "$ST_SEED" "$ST_DIR"
    unset BRIK_INFRA_DIR
  }
  Before 'setup_status'
  After 'cleanup_status'

  seed_deploy() {
    cd "$REPO"
    PATH="${MOCKBIN}:$PATH" cli.deploy.run --version v1.2.3 --environment staging \
      >/dev/null 2>>"${REPO}/.deploy.log"
  }

  It "reports the three layers in agreement after a green deploy (json)"
    status_green() {
      seed_deploy || return $?
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment staging --json 2>/dev/null \
        | jq -r '[.journal.digest,
                  (.desired.definition_hash == .journal.definition_hash),
                  .live.digest, .drift.definition, .drift.live,
                  .drift.corrected_by_reconciler] | @tsv'
    }
    When call status_green
    The status should equal 0
    The output should equal "$(printf '%s\ttrue\t%s\tfalse\tfalse\tfalse' "$DIGEST" "$DIGEST")"
  End

  It "detects live drift on a push-based target, not corrected"
    status_live_drift() {
      seed_deploy || return $?
      # The live state was mutated by hand after the deploy.
      cat > "${MOCKBIN}/kubectl" <<EOF
#!/bin/sh
[ "\$1" = "get" ] && printf 'registry.release/app@${OTHER_DIGEST}' && exit 0
exit 0
EOF
      chmod +x "${MOCKBIN}/kubectl"
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment staging
    }
    When call status_live_drift
    The status should equal 0
    The output should include "LIVE drift detected, NOT corrected"
    The output should include "$OTHER_DIGEST"
    The stderr should be present
  End

  It "detects definition drift when the definition moved since the deploy"
    status_def_drift() {
      seed_deploy || return $?
      # The env definition changes after the deploy (no new version).
      yq -i '.spec.replicas = 3' "$REPO/k8s/deploy.yml"
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment staging
    }
    When call status_def_drift
    The status should equal 0
    The output should include "DEFINITION drift"
    The stderr should be present
  End

  It "never presents the journal alone when the live state is not queryable"
    status_unqueryable() {
      seed_deploy || return $?
      printf '#!/bin/sh\nexit 0\n' > "${MOCKBIN}/kubectl"
      chmod +x "${MOCKBIN}/kubectl"
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment staging
    }
    When call status_unqueryable
    The status should equal 0
    The output should include "not queryable"
    The output should include "the journal is intent, not the live state"
    The stderr should be present
  End

  It "reports an empty journal loudly without inventing a state"
    status_no_event() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment staging
    }
    When call status_no_event
    The status should equal 0
    The output should include "no deployed event recorded"
    The stderr should be present
  End

  It "requires --environment"
    When call cli.status.run
    The status should equal 2
    The stderr should include "requires --environment"
  End

  It "rejects an unknown environment"
    status_badenv() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" cli.status.run --environment ghost
    }
    When call status_badenv
    The status should equal 7
    The stderr should include "unknown deploy environment"
    The stderr should be present
  End
End
