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
