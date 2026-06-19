#!/usr/bin/env bash
# credential_methods_spec.sh - D10 (chantier #39 P1/T2): the Credential schema
# gains two auth methods - workload-identity (ambient OIDC token, no static
# secret) and mtls (client cert + key, by reference). Validated through the real
# infra.validate path against schemas/referential/v1/credential.schema.json.

Describe "credential auth methods (D10: workload-identity, mtls)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"

  validator_missing() {
    ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1
  }

  make_instance() {
    INFRA_DIR="$(mktemp -d)"
    mkdir -p "$INFRA_DIR/endpoints" "$INFRA_DIR/credentials" "$INFRA_DIR/bindings"
    cat > "$INFRA_DIR/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-lab
YAML
    export BRIK_INFRA_DIR="$INFRA_DIR"
  }
  cleanup_instance() { rm -rf "$INFRA_DIR"; unset BRIK_INFRA_DIR INFRA_DIR; }
  Before 'make_instance'
  After 'cleanup_instance'

  It "accepts a workload-identity credential (no static secret)"
    Skip if "no JSON Schema validator on PATH" validator_missing
    wi_ok() {
      cat > "$INFRA_DIR/credentials/wi.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: wi
method: workload-identity
YAML
      infra.validate
    }
    When call wi_ok
    The status should equal 0
    The error should equal ""
  End

  It "accepts an mtls credential (client cert + key by reference)"
    Skip if "no JSON Schema validator on PATH" validator_missing
    mtls_ok() {
      cat > "$INFRA_DIR/credentials/mtls.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: mtls
method: mtls
client_cert: file://trust/client.crt
client_key: env://BRIK_MTLS_KEY
YAML
      infra.validate
    }
    When call mtls_ok
    The status should equal 0
    The error should equal ""
  End

  It "rejects (7) an mtls credential missing client_key"
    Skip if "no JSON Schema validator on PATH" validator_missing
    mtls_bad() {
      cat > "$INFRA_DIR/credentials/mtls.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: mtls
method: mtls
client_cert: file://trust/client.crt
YAML
      infra.validate
    }
    When call mtls_bad
    The status should equal 7
    The stderr should include "Credential"
  End

  It "rejects (7) a workload-identity credential carrying a static secret"
    Skip if "no JSON Schema validator on PATH" validator_missing
    wi_bad() {
      cat > "$INFRA_DIR/credentials/wi.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: wi
method: workload-identity
token: env://SHOULD_NOT_BE_HERE
YAML
      infra.validate
    }
    When call wi_bad
    The status should equal 7
    The stderr should include "Credential"
  End

  It "mtls references resolve through the generic resolver"
    resolve_cert() {
      BRIK_MTLS_KEY="key-material" infra.resolve_ref "env://BRIK_MTLS_KEY"
    }
    When call resolve_cert
    The output should equal "key-material"
  End
End
