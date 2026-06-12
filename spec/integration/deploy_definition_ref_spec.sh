Describe "brik deploy resolves the definition at the version git ref (T6)"
  # The co-versioned guarantee: deploying version V applies the manifest as it
  # was AT V's tag, not the current working tree. A later edit on the base must
  # not leak into a re-deploy of the older version.

  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_repo() {
    # Pin the in-process (in-container) execution path: these examples
    # exercise the verb business logic, not the containerized engine.
    export BRIK_LOCAL_CONTAINER=1
    mock.infra.setup
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
  name: cd-defref
deploy:
  environments:
    staging:
      target: k8s
      manifest: k8s/deploy.yml
      namespace: staging
YAML
      mkdir -p k8s
      cat > k8s/deploy.yml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:old
YAML
      git add -A >/dev/null
      git commit -q -m "v1 baseline"
      git tag v1.0.0
      # Move the base forward AFTER the tag: replicas 1 -> 9 on main.
      sed -i.bak 's/replicas: 1/replicas: 9/' k8s/deploy.yml && rm -f k8s/deploy.yml.bak
      git add -A >/dev/null
      git commit -q -m "bump replicas on main"
    )
    printf '#!/bin/sh\n[ "$1" = "apply" ] && cat "$3"\nexit 0\n' > "${MOCKBIN}/kubectl"
    chmod +x "${MOCKBIN}/kubectl"
  }
  cleanup_repo() { rm -rf "$REPO" "$MOCKBIN";  mock.infra.teardown; }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "applies the tagged version's manifest, not HEAD's"
    deploy_v100() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.0.0 --environment staging
    }
    When call deploy_v100
    The status should equal 0
    The output should include "replicas: 1"
    The output should not include "replicas: 9"
    The stderr should include "resolving deployment definition at v1.0.0"
  End

  It "resolves the tag via tag_prefix when the version is unprefixed"
    deploy_unprefixed() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version 1.0.0 --environment staging
    }
    When call deploy_unprefixed
    The status should equal 0
    The output should include "replicas: 1"
    The stderr should include "resolving deployment definition at v1.0.0"
  End

  It "falls back to the current tree when no tag matches the version"
    deploy_notag() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v2.0.0 --environment staging
    }
    When call deploy_notag
    The status should equal 0
    The output should include "replicas: 9"
    The stderr should include "starting stage: deploy"
  End
End

Describe "brik deploy reads the environment config at config_ref (A3, independent Layer E)"
  # The independent-regime guarantee: an environment that declares config_ref
  # follows that ref for its deployment definition, so its config can change
  # and be redeployed WITHOUT cutting a new version. The artifact stays the
  # one resolved for --version; both layer refs are recorded in the report.

  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_repo() {
    export BRIK_LOCAL_CONTAINER=1
    mock.infra.setup
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
  name: cd-defref-e
deploy:
  environments:
    staging:
      target: k8s
      manifest: k8s/deploy.yml
      namespace: staging
      config_ref: main
YAML
      mkdir -p k8s
      cat > k8s/deploy.yml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:old
YAML
      git add -A >/dev/null
      git commit -q -m "v1 baseline"
      git tag v1.0.0
      # Env config moves forward AFTER the tag: replicas 1 -> 9 on main.
      sed -i.bak 's/replicas: 1/replicas: 9/' k8s/deploy.yml && rm -f k8s/deploy.yml.bak
      git add -A >/dev/null
      git commit -q -m "bump replicas on main"
    )
    printf '#!/bin/sh\n[ "$1" = "apply" ] && cat "$3"\nexit 0\n' > "${MOCKBIN}/kubectl"
    chmod +x "${MOCKBIN}/kubectl"
  }
  cleanup_repo() { rm -rf "$REPO" "$MOCKBIN";  mock.infra.teardown; }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "redeploys an older version with the env config at config_ref's tip"
    deploy_v100() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.0.0 --environment staging
    }
    When call deploy_v100
    The status should equal 0
    The output should include "replicas: 9"
    The output should not include "replicas: 1"
    The stderr should include "resolving environment config for 'staging' at main"
  End

  It "records both layer refs (version_ref + env_config_ref) in the report"
    deploy_and_read_report() {
      cd "$REPO"
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.0.0 --environment staging >/dev/null 2>&1
      jq -r '[.stages[] | select(.stage == "deploy")
              | .business.environments[0] | .version_ref, .env_config_ref] | @tsv' \
        "${BRIK_LOG_DIR}/aggregate-report.json"
    }
    When call deploy_and_read_report
    The status should equal 0
    The output should include "$(git -C "$REPO" rev-parse v1.0.0^{commit})"
    The output should include "$(git -C "$REPO" rev-parse main)"
  End

  It "fails closed when config_ref cannot be resolved"
    deploy_bad_ref() {
      cd "$REPO"
      sed -i.bak 's/config_ref: main/config_ref: no-such-branch/' brik.yml && rm -f brik.yml.bak
      git -C "$REPO" add brik.yml >/dev/null
      git -C "$REPO" commit -q -m "point config_ref at a missing branch"
      git -C "$REPO" tag v1.1.0
      PATH="${MOCKBIN}:$PATH" "$BRIK_BIN" deploy --version v1.1.0 --environment staging
    }
    When call deploy_bad_ref
    The status should equal 7
    The stderr should include "config_ref: cannot resolve 'no-such-branch'"
    The stderr should include "failing closed"
  End
End
