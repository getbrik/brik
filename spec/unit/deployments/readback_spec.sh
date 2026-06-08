Describe "deployments/readback.sh - deployed digest read-back (D5, S6.4)"
  Include "$BRIK_PIPELINE_LIB/version-info.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/_image_ref.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/readback.sh"

  DIGEST="sha256:1111111111111111111111111111111111111111111111111111111111111111"
  OTHER="sha256:2222222222222222222222222222222222222222222222222222222222222222"
  PINNED="nexus.test/brik/app@${DIGEST}"

  # Capture report.record / report.record_object calls into files so each It
  # can assert what the read-back wrote. report.* are stubbed (the real store
  # is exercised by report specs).
  setup() {
    CAP="$(mktemp -d)"
    report.record() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "${CAP}/record"; }
    report.record_object() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "${CAP}/object"; }
    # Default: no resolved ref, no env identity. Each It sets what it needs.
    unset BRIK_DEPLOY_IMAGE_REF BRIK_DRY_RUN 2>/dev/null || true
    unset BRIK_DEPLOY_STAGING_APP_NAME BRIK_DEPLOY_STAGING_AUTH_TOKEN_VAR 2>/dev/null || true
  }
  cleanup() { rm -rf "$CAP"; unset BRIK_DEPLOY_IMAGE_REF BRIK_DRY_RUN 2>/dev/null || true; }
  Before 'setup'
  After 'cleanup'

  recorded_digest() { grep '^deploy|tech|digest|' "${CAP}/record" 2>/dev/null | tail -1 | cut -d'|' -f4; }
  deployed_obj()    { grep '^deploy|tech|deployed|' "${CAP}/object" 2>/dev/null | tail -1 | cut -d'|' -f4-; }

  Describe "always records the resolved digest"
    It "writes deploy.tech.digest from BRIK_DEPLOY_IMAGE_REF (gitops/argocd live match)"
      run_it() {
        export BRIK_DEPLOY_IMAGE_REF="$PINNED"
        export BRIK_DEPLOY_STAGING_APP_NAME="brik-e2e-cd"
        deploy.argocd.get_deployed_digest() { printf '%s' "$DIGEST"; }
        deploy.readback.record --env staging --target gitops --controller argocd
      }
      When call run_it
      The status should be success
      The result of 'recorded_digest()' should equal "$DIGEST"
      The result of 'deployed_obj()' should include "\"live\":\"${DIGEST}\""
      The result of 'deployed_obj()' should include "\"match\":true"
    End
  End

  Describe "mismatch is observed, never fatal (P0)"
    It "records match=false and warns when live != resolved"
      run_it() {
        export BRIK_DEPLOY_IMAGE_REF="$PINNED"
        export BRIK_DEPLOY_STAGING_APP_NAME="brik-e2e-cd"
        deploy.argocd.get_deployed_digest() { printf '%s' "$OTHER"; }
        deploy.readback.record --env staging --target gitops --controller argocd
      }
      When call run_it
      The status should be success
      The result of 'deployed_obj()' should include "\"match\":false"
      The stderr should include "mismatch"
    End
  End

  Describe "targets without a read-back primitive"
    It "marks live unsupported for helm without failing"
      run_it() {
        export BRIK_DEPLOY_IMAGE_REF="$PINNED"
        deploy.readback.record --env staging --target helm
      }
      When call run_it
      The status should be success
      The result of 'recorded_digest()' should equal "$DIGEST"
      The result of 'deployed_obj()' should include "\"live\":\"unsupported\""
      The result of 'deployed_obj()' should include "\"match\":false"
    End
  End

  Describe "dry-run skips the live query"
    It "records live=skipped under BRIK_DRY_RUN"
      run_it() {
        export BRIK_DEPLOY_IMAGE_REF="$PINNED"
        export BRIK_DRY_RUN="true"
        export BRIK_DEPLOY_STAGING_APP_NAME="brik-e2e-cd"
        deploy.argocd.get_deployed_digest() { printf '%s' "$DIGEST"; }
        deploy.readback.record --env staging --target gitops --controller argocd
      }
      When call run_it
      The status should be success
      The result of 'deployed_obj()' should include "\"live\":\"skipped\""
    End
  End

  Describe "no resolved ref (CI deploy without channel)"
    It "records digest=unknown and match=false"
      run_it() {
        deploy.readback.record --env staging --target helm
      }
      When call run_it
      The status should be success
      The result of 'recorded_digest()' should equal "unknown"
      The result of 'deployed_obj()' should include "\"match\":false"
    End
  End
End
