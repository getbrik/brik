#shellcheck shell=bash
# The publishers honour a declared PackageRegistry endpoint: url and
# credential come from the referential, not the BRIK_PUBLISH_* variables.
# One absorbed-path example per module; pkg.endpoint.resolve's own contract
# (conflicts, custom-ca, multiplicity) lives in endpoint_spec.sh.

Describe "publishers x PackageRegistry endpoint"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/secrets.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/_endpoint.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/npm.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/pypi.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/maven.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/cargo.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/nuget.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  write_endpoint() {
    local format="$1" url="$2"
    cat > "$BRIK_INFRA_DIR/endpoints/pkg-${format}.yml" <<YAML
apiVersion: brik.dev/referential/v1
kind: PackageRegistry
name: pkg-${format}
format: ${format}
url: ${url}
credential: pkg-publish
tls:
  trust: system
YAML
    cat > "$BRIK_INFRA_DIR/credentials/pkg-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: pkg-publish
method: token
token: env://LAB_PKG_TOKEN
YAML
  }

  setup_ws() {
    mock.setup
    mock.infra.setup
    mkdir -p "$BRIK_INFRA_DIR/endpoints" "$BRIK_INFRA_DIR/credentials"
    TEST_WS="$(mktemp -d)"
    export LAB_PKG_TOKEN="s3cret"
    ORIG_DIR="$(pwd)"
    cd "$TEST_WS" || return 1
  }
  cleanup_ws() {
    cd "$ORIG_DIR" || true
    mock.cleanup
    mock.infra.teardown
    unset LAB_PKG_TOKEN
    rm -rf "$TEST_WS"
  }
  Before 'setup_ws'
  After 'cleanup_ws'

  It "npm publishes to the endpoint url with the referenced token"
    npm_absorbed() {
      printf '{"name":"t","version":"1.0.0"}\n' > package.json
      MOCK_LOG="${TEST_WS}/npm.log"
      mock.create_logging "npm" "$MOCK_LOG"
      mock.activate
      write_endpoint npm "http://nexus.lab:8081/repository/brik-npm/"
      HOME="$TEST_WS" pkg.npm.publish
      cat "$MOCK_LOG"
    }
    When call npm_absorbed
    The status should be success
    The output should include "--registry http://nexus.lab:8081/repository/brik-npm/"
    The contents of file "${TEST_WS}/.npmrc" should include "_auth=s3cret"
    The stderr should include "plain http"
  End

  It "pypi targets the endpoint url (dry-run command carries it)"
    pypi_absorbed() {
      # Pin the publish tool: detection probes the host PATH for
      # poetry/uv/twine, so an unmocked run tests the host, not the contract.
      mock.create_exit "uv" 0
      mock.activate
      write_endpoint pypi "http://nexus.lab:8081/repository/brik-pypi/"
      BRIK_DRY_RUN=true CI="" pkg.pypi.publish
    }
    When call pypi_absorbed
    The status should be success
    The stderr should include "http://nexus.lab:8081/repository/brik-pypi/"
  End

  It "maven refuses a token credential (username + password required)"
    maven_token() {
      printf '<project/>\n' > pom.xml
      mock.create_exit "mvn" 0
      mock.activate
      write_endpoint maven "http://nexus.lab:8081/repository/brik-maven/"
      pkg.maven.publish
    }
    When call maven_token
    The status should equal 7
    The stderr should include "token credential cannot serve maven"
  End

  It "maven maps a basic credential to the settings.xml pair"
    maven_basic() {
      printf '<project/>\n' > pom.xml
      MOCK_LOG="${TEST_WS}/mvn.log"
      mock.create_logging "mvn" "$MOCK_LOG"
      mock.activate
      write_endpoint maven "http://nexus.lab:8081/repository/brik-maven/"
      cat > "$BRIK_INFRA_DIR/credentials/pkg-publish.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: pkg-publish
method: basic
username: publisher
password: env://LAB_PKG_TOKEN
YAML
      pkg.maven.publish
      cat "$MOCK_LOG"
    }
    When call maven_basic
    The status should be success
    The output should include "brik::default::http://nexus.lab:8081/repository/brik-maven/"
    The output should include "--settings"
    The stderr should include "plain http"
  End

  It "cargo exports the endpoint index and the referenced token"
    cargo_absorbed() {
      printf '[package]\nname = "t"\nversion = "0.1.0"\n' > Cargo.toml
      MOCK_LOG="${TEST_WS}/cargo.log"
      # The index and token travel as env vars (and are scrubbed after the
      # publish), so the mock dumps what the cargo process actually saw.
      printf '#!/bin/sh\necho "INDEX=$CARGO_REGISTRIES_BRIK_INDEX TOKEN=$CARGO_REGISTRIES_BRIK_TOKEN" >> "%s"\n' \
        "$MOCK_LOG" > "${MOCK_BIN}/cargo"
      chmod +x "${MOCK_BIN}/cargo"
      mock.activate
      write_endpoint cargo "http://nexus.lab:8081/repository/brik-cargo/"
      pkg.cargo.publish --registry brik
      cat "$MOCK_LOG"
    }
    When call cargo_absorbed
    The status should be success
    The output should include "INDEX=http://nexus.lab:8081/repository/brik-cargo/ TOKEN=s3cret"
    The stderr should include "plain http"
  End

  It "nuget derives allowInsecureConnections from the declared posture only"
    nuget_absorbed() {
      MOCK_LOG="${TEST_WS}/dotnet.log"
      mock.create_logging "dotnet" "$MOCK_LOG"
      mock.activate
      mkdir -p nupkg && : > nupkg/t.1.0.0.nupkg
      write_endpoint nuget "http://nexus.lab:8081/repository/brik-nuget/"
      pkg.nuget.publish
      cat "$MOCK_LOG"
    }
    When call nuget_absorbed
    The status should be success
    The output should include "--configfile"
    The output should include "--source brik"
    The stderr should include "plain http"
  End

  It "nuget over declared https does not allow insecure connections"
    nuget_https() {
      MOCK_LOG="${TEST_WS}/dotnet.log"
      mock.create_logging "dotnet" "$MOCK_LOG"
      mock.activate
      mkdir -p nupkg && : > nupkg/t.1.0.0.nupkg
      write_endpoint nuget "https://nexus.lab:8443/repository/brik-nuget/"
      pkg.nuget.publish
      cat "$MOCK_LOG"
    }
    When call nuget_https
    The status should be success
    The output should include "--source https://nexus.lab:8443/repository/brik-nuget/"
    The output should not include "--configfile"
    The stderr should include "publishing"
  End
End
