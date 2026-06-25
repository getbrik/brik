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

    It "rejects (7) an endpoint referencing an unknown credential"
      dangling_cred() {
        cat > "$INFRA_DIR/endpoints/pkg-npm.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: PackageRegistry
name: pkg-npm
format: npm
url: https://nexus.lab:8443/repository/brik-npm/
credential: no-such-credential
tls:
  trust: system
YAML
        infra.validate
      }
      When call dangling_cred
      The status should equal 7
      The stderr should include "unknown credential 'no-such-credential'"
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
  # infra.env_var_of_ref - echo the variable NAME behind an env:// reference
  # =========================================================================
  Describe "infra.env_var_of_ref"
    It "echoes the variable name behind an env:// ref"
      When call infra.env_var_of_ref "env://GIT_TOKEN"
      The output should equal "GIT_TOKEN"
    End

    It "fails closed (7) for a non-env:// ref (no variable name to hand over)"
      When call infra.env_var_of_ref "file://trust/token"
      The status should equal 7
      The stderr should include "env://"
    End

    It "requires a ref (2)"
      When call infra.env_var_of_ref ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # infra.credential_for_endpoint (PD3) - CI-time, environment-independent
  # =========================================================================
  Describe "infra.credential_for_endpoint"
    Before 'make_instance'
    After 'cleanup_instance'

    # Add a second binding that maps the same endpoint to the same credential:
    # a consistent, environment-independent resolution.
    add_consistent_binding() {
      cat > "$INFRA_DIR/bindings/prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: prod
endpoints:
  registry-candidate: registry-push
YAML
    }

    # A divergent second binding: same endpoint, different credential. CI-time
    # resolution is genuinely ambiguous and must fail closed.
    add_divergent_binding() {
      cat > "$INFRA_DIR/credentials/registry-prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry-prod
method: basic
username: env://BRIK_REGISTRY_USER
password: env://BRIK_REGISTRY_PASSWORD
YAML
      cat > "$INFRA_DIR/bindings/prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: prod
endpoints:
  registry-candidate: registry-prod
YAML
    }

    It "resolves the credential bound to an endpoint, env-independently"
      resolve() { add_consistent_binding; infra.credential_for_endpoint registry-candidate; }
      When call resolve
      The output should include '"name": "registry-push"'
      The output should include '"method": "basic"'
    End

    It "resolves from a single binding too"
      When call infra.credential_for_endpoint registry-candidate
      The output should include '"name": "registry-push"'
    End

    It "fails closed (7) when environments bind divergent credentials"
      diverge() { add_divergent_binding; infra.credential_for_endpoint registry-candidate; }
      When call diverge
      The status should equal 7
      The stderr should include "registry-candidate"
      The stderr should include "divergent"
    End

    It "fails closed (7) when no binding maps the endpoint"
      When call infra.credential_for_endpoint argocd
      The status should equal 7
      The stderr should include "argocd"
    End

    It "requires an endpoint name (2)"
      When call infra.credential_for_endpoint ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # infra.evidence_token_var (PD3, T5d) - the state-repo GitHost token var,
  # resolved by target (the evidence repo's host), environment-independent.
  # =========================================================================
  Describe "infra.evidence_token_var"
    Before 'make_instance'
    After 'cleanup_instance'

    # Declare a GitHost serving gitea.lab + a token credential, and bind it.
    add_githost() {
      cat > "$INFRA_DIR/endpoints/git.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git
product: gitea
api_url: https://gitea.lab
git_url: ssh://git@gitea.lab:22
tls:
  trust: system
YAML
      cat > "$INFRA_DIR/credentials/git-token.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: git-token
method: token
token: env://BRIK_GIT_TOKEN
YAML
      cat > "$INFRA_DIR/bindings/e2e.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: e2e
endpoints:
  registry-candidate: registry-push
  git: git-token
YAML
    }

    It "resolves the GitHost token var by target, env-independently"
      resolve() { add_githost; infra.evidence_token_var "https://gitea.lab/brik/brik-state.git"; }
      When call resolve
      The output should equal "BRIK_GIT_TOKEN"
    End

    It "matches the host even when the repo URL declares a port"
      resolve() { add_githost; infra.evidence_token_var "https://gitea.lab:443/brik/brik-state.git"; }
      When call resolve
      The output should equal "BRIK_GIT_TOKEN"
    End

    It "echoes nothing (legacy fallback) when no referential is configured"
      no_infra() { unset BRIK_INFRA_DIR; infra.evidence_token_var "https://gitea.lab/brik/state.git"; }
      When call no_infra
      The output should equal ""
      The status should equal 0
    End

    It "echoes nothing (legacy fallback) when no GitHost matches the repo host"
      resolve() { add_githost; infra.evidence_token_var "https://other.example/brik/state.git"; }
      When call resolve
      The output should equal ""
      The status should equal 0
    End

    It "fails closed (7) when the GitHost is declared but its credential is unbound"
      # GitHost present, but no binding maps it: a genuine config gap, not a
      # reason to silently fall back to a brik.yml token_var.
      unbound() {
        cat > "$INFRA_DIR/endpoints/git.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git
product: gitea
api_url: https://gitea.lab
git_url: https://gitea.lab
tls:
  trust: system
YAML
        infra.evidence_token_var "https://gitea.lab/brik/state.git"
      }
      When call unbound
      The status should equal 7
      The stderr should include "git"
    End

    It "requires a repo URL (2)"
      When call infra.evidence_token_var ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # infra.capability_norm (D11) - single read path, object output
  # =========================================================================
  Describe "infra.capability_norm"
    norm() { infra.capability_norm "$1"; }

    It "normalizes a scalar provider string to {provider, endpoint:null}"
      When call norm '"cosign-keyless"'
      The output should equal '{"provider":"cosign-keyless","endpoint":null}'
    End

    It "normalizes an object {provider, endpoint} unchanged"
      When call norm '{"provider":"cosign-keyless","endpoint":"signing"}'
      The output should equal '{"provider":"cosign-keyless","endpoint":"signing"}'
    End

    It "fills endpoint:null when the object omits endpoint"
      When call norm '{"provider":"cosign-keyless"}'
      The output should equal '{"provider":"cosign-keyless","endpoint":null}'
    End

    It "rejects (7) an object without a provider"
      When call norm '{"endpoint":"signing"}'
      The status should equal 7
      The stderr should include "provider"
    End

    It "rejects (7) a non string/object value"
      When call norm '42'
      The status should equal 7
      The stderr should include "provider string or {provider, endpoint?}"
    End

    It "rejects (2) an empty value"
      When call norm ''
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # Binding.capabilities accepts both forms (schema, D11)
  # =========================================================================
  Describe "Binding.capabilities both forms validate"
    Before 'make_instance'
    After 'cleanup_instance'

    # Rewrite the binding with capabilities in either form and run the full
    # referential validation (schema included). Capabilities are not
    # reference-checked (only .endpoints is), so the endpoint string in the
    # object form is a pattern-validated label, not a declared endpoint.
    bind_capabilities() {
      cat > "$INFRA_DIR/bindings/e2e.yml" <<YAML
apiVersion: brik.dev/referential/v1
kind: Binding
name: e2e
endpoints:
  registry-candidate: registry-push
capabilities:
${1}
YAML
      infra.validate
    }

    It "accepts the scalar provider form"
      Skip if "no JSON Schema validator" validator_missing
      When call bind_capabilities "  artifact-attestation: cosign-keyless"
      The status should equal 0
    End

    It "accepts the object {provider, endpoint} form"
      Skip if "no JSON Schema validator" validator_missing
      cap_object() {
        bind_capabilities "  artifact-attestation:
    provider: cosign-keyless
    endpoint: signing"
      }
      When call cap_object
      The status should equal 0
    End
  End

  # =========================================================================
  # infra.tls_ca
  # =========================================================================
  Describe "infra.tls_ca"
    Before 'make_instance'
    After 'cleanup_instance'

    custom_ca_endpoint() {
      jq -n '{kind: "Registry", name: "secure",
              url: "https://nexus.lab:8443/repository/docker",
              tls: {trust: "custom-ca"}}'
    }

    It "is empty for system trust"
      tls_system() {
        infra.tls_ca "$(jq -n '{url: "https://r.example", tls: {trust: "system"}}')"
      }
      When call tls_system
      The status should be success
      The output should equal ""
    End

    It "is empty for insecure trust"
      tls_insecure() {
        infra.tls_ca "$(jq -n '{url: "http://r.example", tls: {trust: "insecure"}}')"
      }
      When call tls_insecure
      The status should be success
      The output should equal ""
    End

    It "resolves the bundle by the trust/ca/<hostname>/ convention (port and path stripped)"
      tls_resolved() {
        mkdir -p "$INFRA_DIR/trust/ca/nexus.lab"
        printf 'PEM\n' > "$INFRA_DIR/trust/ca/nexus.lab/ca.crt"
        infra.tls_ca "$(custom_ca_endpoint)"
      }
      When call tls_resolved
      The status should be success
      The output should equal "$INFRA_DIR/trust/ca/nexus.lab/ca.crt"
    End

    It "fails closed when custom-ca is declared but the bundle is absent"
      tls_missing() {
        infra.tls_ca "$(custom_ca_endpoint)"
      }
      When call tls_missing
      The status should equal 7
      The stderr should include "trust/ca/nexus.lab"
    End

    It "resolves a GitHost endpoint through its api_url"
      tls_githost() {
        mkdir -p "$INFRA_DIR/trust/ca/gitea.lab"
        printf 'PEM\n' > "$INFRA_DIR/trust/ca/gitea.lab/ca.crt"
        infra.tls_ca "$(jq -n '{kind: "GitHost", name: "git",
                                api_url: "https://gitea.lab:3443/api/v1",
                                git_url: "https://gitea.lab:3443",
                                tls: {trust: "custom-ca"}}')"
      }
      When call tls_githost
      The status should be success
      The output should equal "$INFRA_DIR/trust/ca/gitea.lab/ca.crt"
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
  # infra.ssh_target_for
  # =========================================================================
  Describe "infra.ssh_target_for"
    Before 'make_instance'
    After 'cleanup_instance'

    It "echoes the SshTarget declaring the host"
      ssh_target_match() {
        cat > "$INFRA_DIR/endpoints/ssh-prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: SshTarget
name: ssh-prod
hosts:
  - deploy.example.com
  - deploy2.example.com
strict_host_key: false
YAML
        infra.ssh_target_for "deploy2.example.com"
      }
      When call ssh_target_match
      The output should include '"name": "ssh-prod"'
    End

    It "fails closed (7) for an undeclared host"
      When call infra.ssh_target_for "ghost.example.com"
      The status should equal 7
      The stderr should include "ghost.example.com"
    End
  End

  # =========================================================================
  # infra.endpoint_of_kind
  # =========================================================================
  Describe "infra.endpoint_of_kind"
    Before 'make_instance'
    After 'cleanup_instance'

    write_signing() {
      cat > "$INFRA_DIR/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: keyless
transparency: rekor-public
YAML
    }

    It "echoes the single endpoint of the kind"
      single_kind() { write_signing; infra.endpoint_of_kind Signing; }
      When call single_kind
      The output should include '"backend": "keyless"'
    End

    It "fails closed (7) when no endpoint of the kind is declared"
      When call infra.endpoint_of_kind Signing
      The status should equal 7
      The stderr should include "Signing"
    End

    It "fails closed (7) when several endpoints of the kind are declared"
      ambiguous_kind() {
        write_signing
        cp "$INFRA_DIR/endpoints/signing.yml" "$INFRA_DIR/endpoints/signing-bis.yml"
        yq -i '.name = "signing-bis"' "$INFRA_DIR/endpoints/signing-bis.yml"
        infra.endpoint_of_kind Signing
      }
      When call ambiguous_kind
      The status should equal 7
      The stderr should include "multiple"
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
  # policies/ category and the PackageRegistry / Notification kinds
  # =========================================================================
  Describe "policies category and platform-service kinds"
    Before 'make_instance'
    After 'cleanup_instance'

    write_policy() {
      mkdir -p "$INFRA_DIR/policies"
      cat > "$INFRA_DIR/policies/org.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Policy
name: org
url: https://policy.internal/brik-policy.yml
YAML
    }

    It "accepts a Policy document under policies/"
      policy_valid() { write_policy; infra.validate; }
      When call policy_valid
      The status should be success
      The stderr should equal ""
    End

    It "rejects (7) a Policy document under endpoints/"
      policy_misplaced() {
        cat > "$INFRA_DIR/endpoints/org.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Policy
name: org
url: https://policy.internal/brik-policy.yml
YAML
        infra.validate
      }
      When call policy_misplaced
      The status should equal 7
      The stderr should include "Policy"
    End

    It "accepts PackageRegistry and Notification endpoints"
      services_valid() {
        cat > "$INFRA_DIR/endpoints/pkg-npm.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: PackageRegistry
name: pkg-npm
format: npm
url: http://nexus.lab:8081/repository/npm-private
tls:
  trust: insecure
YAML
        cat > "$INFRA_DIR/endpoints/notify-slack.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Notification
name: notify-slack
service: slack
url: https://hooks.slack.example/services/T0/B0/x
tls:
  trust: system
YAML
        infra.validate
      }
      When call services_valid
      The status should be success
      The stderr should equal ""
    End

    It "infra.policy echoes the policy document and infra.policy_names lists it"
      policy_accessors() {
        write_policy
        infra.policy org | grep -q '"kind": "Policy"' || return 1
        [[ "$(infra.policy_names)" == "org" ]]
      }
      When call policy_accessors
      The status should be success
    End

    It "infra.policy_names is empty (rc 0) without a policies directory"
      When call infra.policy_names
      The status should be success
      The output should equal ""
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

  # =========================================================================
  # infra.capability_provider - read a Binding's .capabilities[<cap>] and
  # normalize it to {provider, endpoint}. The runtime read path the audit
  # found inert (Binding.capabilities x-pending, capability_norm unconsumed).
  # =========================================================================
  Describe "infra.capability_provider"
    BeforeEach 'make_instance'
    AfterEach 'cleanup_instance'

    bind_cap() {
      # Append a capabilities block to the e2e binding.
      cat >> "$INFRA_DIR/bindings/e2e.yml" <<YAML
capabilities:
  artifact-attestation: $1
YAML
    }

    It "resolves a scalar provider string to {provider, endpoint:null}"
      bind_cap '"cosign-keyless"'
      When call infra.capability_provider e2e artifact-attestation
      The output should equal '{"provider":"cosign-keyless","endpoint":null}'
    End

    It "resolves an object {provider, endpoint}"
      bind_cap '{provider: cosign-keyless, endpoint: sign-prod}'
      When call infra.capability_provider e2e artifact-attestation
      The output should equal '{"provider":"cosign-keyless","endpoint":"sign-prod"}'
    End

    It "fails closed (7) when no binding exists for the environment"
      When call infra.capability_provider ghost-env artifact-attestation
      The status should equal 7
      The stderr should include "ghost-env"
    End

    It "fails closed (7) when the binding declares no such capability"
      When call infra.capability_provider e2e artifact-attestation
      The status should equal 7
      The stderr should include "artifact-attestation"
    End

    It "requires an environment and a capability (2)"
      When call infra.capability_provider e2e ''
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # infra.endpoint_for_capability - join the binding's provider to its
  # endpoint: an explicit binding endpoint wins, else the provider manifest's
  # endpoint_kind resolves via infra.endpoint_of_kind. Closes the chain the
  # provider schema documents: capability -> provider -> endpoint_kind -> endpoint.
  # =========================================================================
  Describe "infra.endpoint_for_capability"
    BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'
    BeforeEach 'make_instance; add_signing'
    AfterEach 'cleanup_instance'

    # A Signing endpoint of the kind cosign-keyless operates against.
    add_signing() {
      cat > "$INFRA_DIR/endpoints/sign-prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: sign-prod
backend: keyless
transparency: none
YAML
    }
    bind_cap() {
      cat >> "$INFRA_DIR/bindings/e2e.yml" <<YAML
capabilities:
  artifact-attestation: $1
YAML
    }

    It "resolves the endpoint by the provider manifest's kind"
      bind_cap '"cosign-keyless"'
      When call infra.endpoint_for_capability e2e artifact-attestation
      The output should include '"name": "sign-prod"'
      The output should include '"kind": "Signing"'
    End

    It "honors an explicit endpoint named in the binding"
      bind_cap '{provider: cosign-keyless, endpoint: sign-prod}'
      When call infra.endpoint_for_capability e2e artifact-attestation
      The output should include '"name": "sign-prod"'
    End

    It "fails closed (7) when the provider is unknown to the registry"
      bind_cap '"no-such-provider"'
      When call infra.endpoint_for_capability e2e artifact-attestation
      The status should equal 7
      The stderr should include "no-such-provider"
    End

    It "fails closed (7) when the provider implements a different capability"
      bind_cap '"oras-transport"'
      When call infra.endpoint_for_capability e2e artifact-attestation
      The status should equal 7
      The stderr should include "capability"
    End

    It "fails closed (7) when no endpoint of the provider's kind is declared"
      rm -f "$INFRA_DIR/endpoints/sign-prod.yml"
      bind_cap '"cosign-keyless"'
      When call infra.endpoint_for_capability e2e artifact-attestation
      The status should equal 7
      The stderr should include "Signing"
    End
  End
End
