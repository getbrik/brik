Describe "transverse/infra.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"

  # Helper: returns 0 when no JSON Schema validator is on PATH.
  validator_missing() {
    ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1
  }

  # Build a minimal valid referential instance (one endpoint, one
  # credential, one binding) and point BRIK_INFRA_DIR at it.
  make_instance() {
    INFRA_DIR="$(mktemp -d)"
    mkdir -p "$INFRA_DIR/endpoints" "$INFRA_DIR/credentials" "$INFRA_DIR/bindings"
    cat > "$INFRA_DIR/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-lab
YAML
    cat > "$INFRA_DIR/endpoints/registry-candidate.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-candidate
url: http://nexus.lab:8082/repository/docker-candidate
tls:
  trust: insecure
YAML
    cat > "$INFRA_DIR/credentials/registry-push.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry-push
method: basic
username: env://BRIK_REGISTRY_USER
password: env://BRIK_REGISTRY_PASSWORD
YAML
    cat > "$INFRA_DIR/bindings/e2e.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: e2e
endpoints:
  registry-candidate: registry-push
YAML
    export BRIK_INFRA_DIR="$INFRA_DIR"
  }

  cleanup_instance() {
    rm -rf "$INFRA_DIR"
    unset BRIK_INFRA_DIR INFRA_DIR
  }

  # =========================================================================
  # infra.root
  # =========================================================================
  Describe "infra.root"
    Before 'make_instance'
    After 'cleanup_instance'

    It "echoes the referential directory from BRIK_INFRA_DIR"
      When call infra.root
      The output should equal "$INFRA_DIR"
    End

    It "fails closed (4) when neither BRIK_INFRA_DIR nor BRIK_INFRA_REPO is set"
      root_unset() { unset BRIK_INFRA_DIR; infra.root; }
      When call root_unset
      The status should equal 4
      The stderr should include "brik infra init"
    End

    It "rejects (4) BRIK_INFRA_DIR and BRIK_INFRA_REPO set together"
      root_both() { BRIK_INFRA_REPO="https://git.example/infra.git" infra.root; }
      When call root_both
      The status should equal 4
      The stderr should include "mutually exclusive"
    End

    It "returns config_error (7) when the directory does not exist"
      root_missing() { BRIK_INFRA_DIR="/nonexistent/infra" infra.root; }
      When call root_missing
      The status should equal 7
      The stderr should include "not found"
    End

    It "returns config_error (7) when referential.yml is absent"
      root_not_instance() {
        local empty; empty="$(mktemp -d)"
        BRIK_INFRA_DIR="$empty" infra.root
        local rc=$?
        rm -rf "$empty"
        return "$rc"
      }
      When call root_not_instance
      The status should equal 7
      The stderr should include "referential.yml"
    End
  End

  # =========================================================================
  # infra.root - BRIK_INFRA_REPO (git clone)
  # =========================================================================
  Describe "infra.root from BRIK_INFRA_REPO"
    setup_repo() {
      make_instance
      REPO_DIR="$(mktemp -d)"
      git -C "$REPO_DIR" init -q -b main
      cp -R "$INFRA_DIR"/. "$REPO_DIR"/
      git -C "$REPO_DIR" add -A
      git -C "$REPO_DIR" -c user.email=t@t -c user.name=t commit -qm referential
      CLONE_LOG_DIR="$(mktemp -d)"
      unset BRIK_INFRA_DIR
      export BRIK_INFRA_REPO="file://$REPO_DIR"
      export BRIK_LOG_DIR="$CLONE_LOG_DIR"
    }
    cleanup_repo() {
      rm -rf "$REPO_DIR" "$CLONE_LOG_DIR" "$INFRA_DIR"
      unset BRIK_INFRA_REPO REPO_DIR CLONE_LOG_DIR INFRA_DIR
    }
    Before 'setup_repo'
    After 'cleanup_repo'

    It "clones the referential repo and echoes the clone path"
      When call infra.root
      The output should equal "$CLONE_LOG_DIR/infra-referential"
      The path "$CLONE_LOG_DIR/infra-referential/referential.yml" should be file
      The stderr should include "unpinned"
    End

    It "checks out the pinned ref given as a URL fragment"
      pinned_root() {
        local sha
        sha="$(git -C "$REPO_DIR" rev-parse HEAD)"
        BRIK_INFRA_REPO="file://${REPO_DIR}#${sha}" infra.root
      }
      When call pinned_root
      The output should equal "$CLONE_LOG_DIR/infra-referential"
      The stderr should equal ""
    End

    It "reuses an existing clone without contacting the remote"
      reuse_clone() {
        infra.root >/dev/null 2>&1 || return $?
        BRIK_INFRA_REPO="file:///nonexistent/unreachable.git" infra.root 2>/dev/null
      }
      When call reuse_clone
      The output should equal "$CLONE_LOG_DIR/infra-referential"
    End
  End

  # =========================================================================
  # infra.validate
  # =========================================================================
  Describe "infra.validate"
    Before 'make_instance'
    After 'cleanup_instance'

    It "accepts a valid instance"
      When call infra.validate
      The status should be success
      The stderr should equal ""
    End

    It "rejects (7) an unexpected apiVersion"
      bad_api() {
        yq -i '.apiVersion = "brik.dev/referential/v2"' "$INFRA_DIR/endpoints/registry-candidate.yml"
        infra.validate
      }
      When call bad_api
      The status should equal 7
      The stderr should include "apiVersion"
    End

    It "rejects (7) a kind with no schema"
      unknown_kind() {
        yq -i '.kind = "Ghost"' "$INFRA_DIR/endpoints/registry-candidate.yml"
        infra.validate
      }
      When call unknown_kind
      The status should equal 7
      The stderr should include "Ghost"
    End

    It "rejects (7) a kind outside its category"
      misplaced_kind() {
        cp "$INFRA_DIR/credentials/registry-push.yml" "$INFRA_DIR/endpoints/sneaky.yml"
        yq -i '.name = "sneaky"' "$INFRA_DIR/endpoints/sneaky.yml"
        infra.validate
      }
      When call misplaced_kind
      The status should equal 7
      The stderr should include "Credential"
    End

    It "rejects (7) duplicate names within a category"
      duplicate_name() {
        cp "$INFRA_DIR/endpoints/registry-candidate.yml" "$INFRA_DIR/endpoints/copy.yml"
        infra.validate
      }
      When call duplicate_name
      The status should equal 7
      The stderr should include "duplicate"
    End

    It "rejects (7) a document missing its name"
      nameless() {
        yq -i 'del(.name)' "$INFRA_DIR/endpoints/registry-candidate.yml"
        infra.validate
      }
      When call nameless
      The status should equal 7
      The stderr should include "name"
    End

    It "rejects (7) a binding referencing an unknown endpoint"
      dangling_endpoint() {
        yq -i '.endpoints = {"ghost-registry": "registry-push"}' "$INFRA_DIR/bindings/e2e.yml"
        infra.validate
      }
      When call dangling_endpoint
      The status should equal 7
      The stderr should include "ghost-registry"
    End

    It "rejects (7) a binding referencing an unknown credential"
      dangling_credential() {
        yq -i '.endpoints = {"registry-candidate": "ghost-cred"}' "$INFRA_DIR/bindings/e2e.yml"
        infra.validate
      }
      When call dangling_credential
      The status should equal 7
      The stderr should include "ghost-cred"
    End

    It "rejects (7) an unsupported category directory holding YAML"
      rogue_category() {
        mkdir -p "$INFRA_DIR/widgets"
        printf 'kind: Widget\n' > "$INFRA_DIR/widgets/w.yml"
        infra.validate
      }
      When call rogue_category
      The status should equal 7
      The stderr should include "widgets"
    End

    It "rejects (7) a schema violation (Registry without url)"
      Skip if "no JSON Schema validator on PATH" validator_missing
      schema_violation() {
        yq -i 'del(.url)' "$INFRA_DIR/endpoints/registry-candidate.yml"
        infra.validate
      }
      When call schema_violation
      The status should equal 7
      The stderr should include "registry-candidate"
    End
  End

  # =========================================================================
  # Document accessors
  # =========================================================================
  Describe "infra accessors"
    Before 'make_instance'
    After 'cleanup_instance'

    It "infra.endpoint echoes the endpoint document as JSON"
      When call infra.endpoint registry-candidate
      The output should include '"kind": "Registry"'
      The output should include 'nexus.lab'
    End

    It "infra.endpoint returns config_error (7) for an unknown name"
      When call infra.endpoint ghost
      The status should equal 7
      The stderr should include "ghost"
    End

    It "infra.credential echoes the credential document as JSON"
      When call infra.credential registry-push
      The output should include '"method": "basic"'
    End

    It "infra.binding echoes the binding for an environment"
      When call infra.binding e2e
      The output should include '"registry-candidate": "registry-push"'
    End

    It "infra.credential_for resolves the credential bound to an endpoint"
      When call infra.credential_for e2e registry-candidate
      The output should include '"name": "registry-push"'
    End

    It "infra.credential_for returns config_error (7) when unbound"
      unbound() {
        cat > "$INFRA_DIR/endpoints/argocd.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: ArgoCD
name: argocd
url: https://argocd.lab:9080
tls:
  trust: system
YAML
        infra.credential_for e2e argocd
      }
      When call unbound
      The status should equal 7
      The stderr should include "argocd"
    End
  End

  # =========================================================================
  # infra.registry_for
  # =========================================================================
  Describe "infra.registry_for"
    Before 'make_instance'
    After 'cleanup_instance'

    It "echoes the Registry endpoint matching the host (with port)"
      When call infra.registry_for "nexus.lab:8082"
      The output should include '"name": "registry-candidate"'
      The stderr should include "plain http"
    End

    It "is silent for a declared https endpoint with system trust"
      registry_https() {
        cat > "$INFRA_DIR/endpoints/registry-secure.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-secure
url: https://harbor.internal:8443
tls:
  trust: system
YAML
        infra.registry_for "harbor.internal:8443"
      }
      When call registry_https
      The output should include '"name": "registry-secure"'
      The stderr should equal ""
    End

    It "warns when an https endpoint declares tls.trust: insecure"
      registry_insecure_tls() {
        cat > "$INFRA_DIR/endpoints/registry-skipverify.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-skipverify
url: https://harbor.internal:8443
tls:
  trust: insecure
YAML
        infra.registry_for "harbor.internal:8443"
      }
      When call registry_insecure_tls
      The output should include '"name": "registry-skipverify"'
      The stderr should include "insecure"
    End

    It "fails closed (7) when the host is not declared"
      When call infra.registry_for "ghost.registry:5000"
      The status should equal 7
      The stderr should include "ghost.registry:5000"
    End

    It "rejects (2) a missing host"
      When call infra.registry_for ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # infra.resolve_ref
  # =========================================================================
  Describe "infra.resolve_ref"
    Before 'make_instance'
    After 'cleanup_instance'

    It "resolves env:// to the variable value"
      resolve_env() {
        export INFRA_SPEC_SECRET="s3cret"
        infra.resolve_ref "env://INFRA_SPEC_SECRET"
        local rc=$?
        unset INFRA_SPEC_SECRET
        return "$rc"
      }
      When call resolve_env
      The output should equal "s3cret"
    End

    It "fails (4) on env:// when the variable is unset"
      When call infra.resolve_ref "env://INFRA_SPEC_UNSET_VAR"
      The status should equal 4
      The stderr should include "INFRA_SPEC_UNSET_VAR"
    End

    It "resolves file:// relative to the referential root"
      resolve_rel() {
        mkdir -p "$INFRA_DIR/trust"
        printf 'pem-bytes' > "$INFRA_DIR/trust/ca.crt"
        infra.resolve_ref "file://trust/ca.crt"
      }
      When call resolve_rel
      The output should equal "pem-bytes"
    End

    It "resolves file:// with an absolute path"
      resolve_abs() {
        local f; f="$(mktemp)"
        printf 'abs-bytes' > "$f"
        infra.resolve_ref "file://$f"
        local rc=$?
        rm -f "$f"
        return "$rc"
      }
      When call resolve_abs
      The output should equal "abs-bytes"
    End

    It "fails (6) on file:// when the file is unreadable"
      When call infra.resolve_ref "file:///nonexistent/ca.crt"
      The status should equal 6
      The stderr should include "nonexistent"
    End

    It "fails (3) on bao:// while the OpenBAO provider is not wired"
      When call infra.resolve_ref "bao://secret/ci/registry#password"
      The status should equal 3
      The stderr should include "OpenBAO"
    End

    It "rejects (2) an unknown reference scheme"
      When call infra.resolve_ref "vault://whatever"
      The status should equal 2
      The stderr should include "vault://"
    End
  End

  # =========================================================================
  # infra.fingerprint
  # =========================================================================
  Describe "infra.fingerprint"
    Before 'make_instance'
    After 'cleanup_instance'

    It "is stable for the same content"
      stable() {
        local a b
        a="$(infra.fingerprint)" || return $?
        b="$(infra.fingerprint)" || return $?
        [[ "$a" == "$b" && "$a" =~ ^[0-9a-f]{64}$ ]]
      }
      When call stable
      The status should be success
    End

    It "changes when a document changes"
      drift() {
        local a b
        a="$(infra.fingerprint)" || return $?
        yq -i '.url = "http://nexus.lab:9999"' "$INFRA_DIR/endpoints/registry-candidate.yml"
        b="$(infra.fingerprint)" || return $?
        [[ "$a" != "$b" ]]
      }
      When call drift
      The status should be success
    End
  End
End
