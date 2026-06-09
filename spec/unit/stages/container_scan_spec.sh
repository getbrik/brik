Describe "stages/container_scan.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/context.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/scan.sh"
  Include "$BRIK_HOME/lib/stages/container_scan.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  read_container_scan_status() {
    jq -r '.stages[] | select(.stage == "container-scan") | .tech.status // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  Describe "stages.container_scan"
    Describe "no image configured"
      setup_no_image() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
        export BRIK_RUN_ID="container-scan-spec-fixture"
        report.init >/dev/null 2>&1 || true
        unset BRIK_SECURITY_CONTAINER_IMAGE 2>/dev/null || true
      }
      cleanup_no_image() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        rm -rf "$BRIK_LOG_DIR"
        unset BRIK_RUN_ID 2>/dev/null || true
      }
      Before 'setup_no_image'
      After 'cleanup_no_image'

      It "skips silently when neither the package fragment nor a user override provides an image"
        invoke_skip() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
          local rc=$?
          read_container_scan_status
          return $rc
        }
        When call invoke_skip
        The status should be success
        # Silent skip: no fragment recorded, .tech.status is absent.
        The output should equal ""
      End
    End

    Describe "with image configured auto-loads container module"
      setup_autoload() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        mock.workspace.setup
        mock.setup
        mock.create_exit "grype" 0
        mock.activate
      }
      cleanup_autoload() {
        mock.cleanup
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        mock.workspace.teardown
      }
      Before 'setup_autoload'
      After 'cleanup_autoload'

      It "auto-loads security.container module and runs scan"
        invoke_autoload() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
        }
        When call invoke_autoload
        The status should be success
      End
    End

    Describe "with image and mock scanner"
      setup_with_scanner() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n    severity: critical\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        mock.workspace.setup
        verify.scan.container.run() { return 0; }
      }
      cleanup_with_scanner() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        mock.workspace.teardown
        unset -f verify.scan.container.run 2>/dev/null || true
      }
      Before 'setup_with_scanner'
      After 'cleanup_with_scanner'

      It "returns 0 when the scan passes"
        invoke_success() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
        }
        When call invoke_success
        The status should be success
      End
    End

    Describe "with image and failing scanner"
      setup_failing_scanner() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        mock.workspace.setup
        verify.scan.container.run() { return 1; }
      }
      cleanup_failing_scanner() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        mock.workspace.teardown
        unset -f verify.scan.container.run 2>/dev/null || true
      }
      Before 'setup_failing_scanner'
      After 'cleanup_failing_scanner'

      It "returns non-zero when the scan fails"
        invoke_fail() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
        }
        When call invoke_fail
        The status should equal 10
      End
    End

    Describe "C.4 enrichment with image configured"
      setup_c4() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:1.0.0\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        mock.workspace.setup
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
        export BRIK_RUN_ID="cs-c4-fixture"
        report.init >/dev/null 2>&1 || true
        verify.scan.container.run() { return 0; }
        verify.scan.run() { return 0; }
      }
      cleanup_c4() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        rm -rf "$BRIK_LOG_DIR"
        mock.workspace.teardown
        unset -f verify.scan.container.run verify.scan.run 2>/dev/null || true
        unset BRIK_RUN_ID 2>/dev/null || true
      }
      Before 'setup_c4'
      After 'cleanup_c4'

      read_cs_tech() {
        local key="$1"
        jq -r --arg k "$key" \
          '.stages[] | select(.stage == "container-scan") | .tech[$k] // empty' \
          "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
      }

      It "records container-scan.tech.target_image"
        invoke_target() {
          stages.container_scan "$CTX_FILE" >/dev/null 2>&1
          read_cs_tech "target_image"
        }
        When call invoke_target
        The output should equal "myapp:1.0.0"
      End

      It "records container-scan.tech.tool defaulting when no override"
        invoke_tool() {
          stages.container_scan "$CTX_FILE" >/dev/null 2>&1
          read_cs_tech "tool"
        }
        When call invoke_tool
        The output should equal "auto"
      End

      It "records container-scan.tech.target_digest from the package fragment when present"
        invoke_target_digest() {
          mkdir -p "$BRIK_WORKSPACE/brik-artifacts"
          mkdir -p "$BRIK_WORKSPACE/brik-artifacts/package" && cat > "$BRIK_WORKSPACE/brik-artifacts/package/package.json" <<'JSON'
{
  "schema_version": "1.0",
  "stage": "package",
  "tech": {
    "image_built": "true",
    "image_ref": "myapp:1.0.0"
  },
  "business": {
    "image": {
      "name": "myapp",
      "tag": "1.0.0",
      "full_name": "myapp:1.0.0",
      "digest": "sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
    }
  }
}
JSON
          stages.container_scan "$CTX_FILE" >/dev/null 2>&1
          read_cs_tech "target_digest"
        }
        When call invoke_target_digest
        The output should equal "sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
      End

      It "omits container-scan.tech.target_digest when the package fragment has no digest"
        invoke_no_digest() {
          mkdir -p "$BRIK_WORKSPACE/brik-artifacts"
          mkdir -p "$BRIK_WORKSPACE/brik-artifacts/package" && cat > "$BRIK_WORKSPACE/brik-artifacts/package/package.json" <<'JSON'
{
  "schema_version": "1.0",
  "stage": "package",
  "tech": {
    "image_built": "true",
    "image_ref": "myapp:1.0.0"
  }
}
JSON
          stages.container_scan "$CTX_FILE" >/dev/null 2>&1
          jq -r '.stages[] | select(.stage == "container-scan") | .tech | has("target_digest")' \
            "$BRIK_LOG_DIR/aggregate-report.json"
        }
        When call invoke_no_digest
        The output should equal "false"
      End

      It "records container-scan.tech.scan_duration_ms"
        invoke_scan_duration() {
          stages.container_scan "$CTX_FILE" >/dev/null 2>&1
          read_cs_tech "scan_duration_ms"
        }
        When call invoke_scan_duration
        The output should match pattern "[0-9]*"
      End
    End

    # Evidence signing: the post-scan step that attaches a signed SBOM +
    # provenance to the published digest. cosign/syft are stubbed so the
    # contract checks orchestration, not the real signer.
    Describe "_stages.container_scan._sign_evidence"
      REF="registry.example.com/app@sha256:2222222222222222222222222222222222222222222222222222222222222222"

      setup_sign() {
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
        brik.use() { :; }
        attest.provenance_predicate() { printf '{}'; }
        log.info() { :; }
        log.warn() { :; }
        log.error() { :; }
      }
      cleanup_sign() { rm -rf "$BRIK_LOG_DIR"; }
      Before 'setup_sign'
      After 'cleanup_sign'

      It "skips (rc 0) when no signer is on the runner"
        attest.available() { return 1; }
        When call _stages.container_scan._sign_evidence "$REF"
        The status should be success
      End

      It "signs the digest when cosign and syft are present"
        attest.available() { return 0; }
        syft() { : >"${BRIK_LOG_DIR}/evidence/sbom.cyclonedx.json"; }
        signed_ref=""
        attest.sign() { signed_ref="$1"; return 0; }
        invoke_sign() {
          _stages.container_scan._sign_evidence "$REF"
          local rc=$?
          printf '%s' "$signed_ref"
          return $rc
        }
        When call invoke_sign
        The status should be success
        The output should equal "$REF"
        The path "${BRIK_LOG_DIR}/evidence/provenance.slsa.json" should be exist
      End

      It "fails when signing is attempted but cosign fails"
        attest.available() { return 0; }
        syft() { : >"${BRIK_LOG_DIR}/evidence/sbom.cyclonedx.json"; }
        attest.sign() { return 5; }
        When call _stages.container_scan._sign_evidence "$REF"
        The status should be failure
      End

      Describe "_record_evidence"
        It "self-skips when no evidence repo is configured"
          config.get() { printf '%s' "${2:-}"; }   # every key resolves to its default
          When call _stages.container_scan._record_evidence "$REF" /tmp/sbom.json /tmp/prov.json
          The status should be success
        End

        It "publishes evidence when artifacts.evidence.repo is set"
          config.get() {
            case "$1" in
              .artifacts.evidence.repo) printf 'https://git/state.git' ;;
              *) printf '%s' "${2:-}" ;;
            esac
          }
          evidence.build() { printf '{}'; }
          # publish runs on the right of a pipe (subshell) in the module, so
          # record the repo it was called with to a file.
          REPO_REC="$(mktemp)"
          evidence.publish() {
            while [[ $# -gt 0 ]]; do [[ "$1" == "--repo" ]] && printf '%s' "$2" >"$REPO_REC"; shift; done
            cat >/dev/null
          }
          run_rec() {
            _stages.container_scan._record_evidence "$REF" /tmp/sbom.json /tmp/prov.json
            cat "$REPO_REC"; rm -f "$REPO_REC"
          }
          When call run_rec
          The status should be success
          The output should equal "https://git/state.git"
        End
      End
    End
  End
End
