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

  It "echoes nothing (rc 0) when no endpoint of the format is declared"
    When call pkg.endpoint.resolve npm
    The status should be success
    The output should equal ""
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
