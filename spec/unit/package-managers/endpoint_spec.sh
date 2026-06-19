#shellcheck shell=bash
# pkg.endpoint.resolve - the publishers' referential contract: one
# PackageRegistry endpoint per format provides url + transport posture +
# referenced credential; absence keeps the legacy per-manager variables.

Describe "pkg._endpoint"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/_endpoint.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  setup_infra() {
    mock.infra.setup
    mkdir -p "$BRIK_INFRA_DIR/endpoints" "$BRIK_INFRA_DIR/credentials"
  }
  cleanup_infra() { mock.infra.teardown; }
  BeforeEach setup_infra
  AfterEach cleanup_infra

  write_npm_endpoint() {
    cat > "$BRIK_INFRA_DIR/endpoints/pkg-npm.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: PackageRegistry
name: pkg-npm
format: npm
url: http://nexus.lab:8081/repository/brik-npm/
credential: npm-publish
tls:
  trust: system
YAML
    cat > "$BRIK_INFRA_DIR/credentials/npm-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: npm-publish
method: token
token: env://LAB_NPM_TOKEN
YAML
  }

  It "requires a format (rc 2) when none is given"
    When call pkg.endpoint.resolve ""
    The status should equal 2
    The stderr should include "a format is required"
  End

  It "echoes nothing (rc 0) when the referential is unconfigured"
    no_infra() {
      mock.infra.teardown
      unset BRIK_INFRA_DIR
      pkg.endpoint.resolve npm
    }
    When call no_infra
    The status should be success
    The output should equal ""
  End

  It "echoes nothing (rc 0) when no endpoint of the format is declared"
    When call pkg.endpoint.resolve npm
    The status should be success
    The output should equal ""
  End

  It "warns and marks insecure on tls.trust: insecure over https"
    preset() {
      write_npm_endpoint
      perl -pi -e 's|http://nexus.lab:8081|https://nexus.lab:8081|; s|trust: system|trust: insecure|' \
        "$BRIK_INFRA_DIR/endpoints/pkg-npm.yml"
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should be success
    The output should include '"insecure":true'
    The stderr should include "tls.trust: insecure"
  End

  It "resolves a none-method credential (no token, no basic vars)"
    preset() {
      write_npm_endpoint
      cat > "$BRIK_INFRA_DIR/credentials/npm-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: npm-publish
method: none
YAML
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should be success
    The output should include '"method":"none"'
    The output should include '"token_var":""'
    The stderr should include "plain http"
  End

  It "fails closed on a credential method no publisher can consume"
    preset() {
      write_npm_endpoint
      cat > "$BRIK_INFRA_DIR/credentials/npm-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: npm-publish
method: ssh-key
key: env://LAB_NPM_KEY
YAML
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should equal 7
    The stderr should include "ssh-key"
  End

  It "resolves url, posture and the token credential var of the format"
    preset() { write_npm_endpoint; pkg.endpoint.resolve npm; }
    When call preset
    The status should be success
    The output should include '"url":"http://nexus.lab:8081/repository/brik-npm/"'
    The output should include '"method":"token"'
    The output should include '"token_var":"LAB_NPM_TOKEN"'
    The output should include '"insecure":true'
    The stderr should include "plain http"
  End

  It "maps a basic credential to username + password var"
    preset() {
      write_npm_endpoint
      cat > "$BRIK_INFRA_DIR/credentials/npm-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: npm-publish
method: basic
username: publisher
password: env://LAB_NPM_PASSWORD
YAML
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should be success
    The output should include '"method":"basic"'
    The output should include '"username":"publisher"'
    The output should include '"password_var":"LAB_NPM_PASSWORD"'
    The stderr should include "plain http"
  End

  It "fails closed when the project config contradicts the declared url"
    preset() { write_npm_endpoint; pkg.endpoint.resolve npm "http://elsewhere/"; }
    When call preset
    The status should equal 7
    The stderr should include "failing closed"
  End

  It "fails closed on custom-ca (not wired for package managers)"
    preset() {
      write_npm_endpoint
      perl -pi -e 's|http://nexus.lab:8081|https://nexus.lab:8081|; s|trust: system|trust: custom-ca|' \
        "$BRIK_INFRA_DIR/endpoints/pkg-npm.yml"
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should equal 7
    The stderr should include "custom-ca"
  End

  It "fails closed on a non-env credential reference"
    preset() {
      write_npm_endpoint
      perl -pi -e 's|env://LAB_NPM_TOKEN|file://trust/npm.token|' \
        "$BRIK_INFRA_DIR/credentials/npm-publish.yml"
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should equal 7
    The stderr should include "env://"
  End

  It "fails closed when two endpoints declare the same format"
    preset() {
      write_npm_endpoint
      sed 's/name: pkg-npm/name: pkg-npm-too/' \
        "$BRIK_INFRA_DIR/endpoints/pkg-npm.yml" \
        > "$BRIK_INFRA_DIR/endpoints/pkg-npm-too.yml"
      pkg.endpoint.resolve npm
    }
    When call preset
    The status should equal 7
    The stderr should include "multiple"
  End
End

# pkg.registry.resolve - the container-registry login contract (PD3): the
# brik.yml registry authority matches a Registry endpoint by authority, then
# the credential is resolved by target (infra.credential_for_endpoint, env
# independent). Absence of a matching endpoint keeps the legacy
# BRIK_PUBLISH_DOCKER_*_VAR path.
Describe "pkg.registry.resolve"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/_endpoint.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  setup_infra() {
    mock.infra.setup
    mkdir -p "$BRIK_INFRA_DIR/endpoints" "$BRIK_INFRA_DIR/credentials" \
             "$BRIK_INFRA_DIR/bindings"
  }
  cleanup_infra() { mock.infra.teardown; }
  BeforeEach setup_infra
  AfterEach cleanup_infra

  # A Registry endpoint reachable at nexus.lab:8082 over plain http, a basic
  # credential whose username AND password are env:// references (both become
  # variable names docker login resolves), and a binding wiring them.
  write_registry() {
    cat > "$BRIK_INFRA_DIR/endpoints/oci.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: oci
url: http://nexus.lab:8082
tls:
  trust: system
YAML
    cat > "$BRIK_INFRA_DIR/credentials/registry.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry
method: basic
username: env://OCI_USER
password: env://OCI_PASS
YAML
    cat > "$BRIK_INFRA_DIR/bindings/ci.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: ci
endpoints:
  oci: registry
YAML
  }

  It "echoes nothing (rc 0) when no Registry matches the host (legacy path)"
    When call pkg.registry.resolve other.host:5000
    The status should be success
    The output should equal ""
  End

  It "resolves the basic credential vars by target, env-independently"
    preset() { write_registry; pkg.registry.resolve nexus.lab:8082; }
    When call preset
    The status should be success
    The output should include '"method":"basic"'
    The output should include '"username_var":"OCI_USER"'
    The output should include '"password_var":"OCI_PASS"'
    The output should include '"insecure":true'
    The stderr should include "plain http"
  End

  It "fails closed (7) when the declared registry is unbound"
    preset() {
      write_registry
      rm -f "$BRIK_INFRA_DIR/bindings/ci.yml"
      pkg.registry.resolve nexus.lab:8082
    }
    When call preset
    The status should equal 7
    The stderr should include "oci"
  End

  It "requires a host (2)"
    When call pkg.registry.resolve ""
    The status should equal 2
    The stderr should include "required"
  End

  It "echoes nothing (rc 0) when the referential is unconfigured (legacy)"
    no_infra() {
      mock.infra.teardown
      unset BRIK_INFRA_DIR
      pkg.registry.resolve nexus.lab:8082
    }
    When call no_infra
    The status should be success
    The output should equal ""
  End

  It "warns and marks insecure on tls.trust: insecure over https"
    preset() {
      write_registry
      perl -pi -e 's|http://nexus.lab:8082|https://nexus.lab:8082|; s|trust: system|trust: insecure|' \
        "$BRIK_INFRA_DIR/endpoints/oci.yml"
      pkg.registry.resolve nexus.lab:8082
    }
    When call preset
    The status should be success
    The output should include '"insecure":true'
    The stderr should include "tls.trust: insecure"
  End

  It "resolves a none-method credential (no login vars)"
    preset() {
      write_registry
      cat > "$BRIK_INFRA_DIR/credentials/registry.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry
method: none
YAML
      pkg.registry.resolve nexus.lab:8082
    }
    When call preset
    The status should be success
    The output should include '"method":"none"'
    The output should include '"username_var":""'
    The stderr should include "plain http"
  End

  It "fails closed on a credential method docker login cannot consume"
    preset() {
      write_registry
      cat > "$BRIK_INFRA_DIR/credentials/registry.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry
method: token
token: env://OCI_TOKEN
YAML
      pkg.registry.resolve nexus.lab:8082
    }
    When call preset
    The status should equal 7
    The stderr should include "docker login"
  End

  It "fails closed when the basic username is a non-env reference"
    preset() {
      write_registry
      perl -pi -e 's|env://OCI_USER|file://trust/oci.user|' \
        "$BRIK_INFRA_DIR/credentials/registry.yml"
      pkg.registry.resolve nexus.lab:8082
    }
    When call preset
    The status should equal 7
    The stderr should include "env://"
  End
End
