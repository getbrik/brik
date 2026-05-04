#shellcheck shell=bash disable=SC2148,SC2317

Describe "transverse/sbom.sh"
  Include "$BRIK_TRANSVERSE_LIB/sbom.sh"

  FIX="${BRIK_HOME}/spec/fixtures/sbom"

  Describe "sbom.component_count"
    It "counts 1 component in the osv-scanner fixture"
      When call sbom.component_count "${FIX}/osv-scanner.cdx.json"
      The output should equal "1"
    End

    It "fails with rc=1 when file does not exist"
      When call sbom.component_count "${FIX}/missing.cdx.json"
      The status should be failure
      The stderr should include "does not exist"
    End

    It "fails with rc=2 when no argument is given"
      When call sbom.component_count
      The status should equal 2
      The stderr should include "missing"
    End
  End

  Describe "sbom.vuln_count"
    It "counts 1 vulnerability in the osv-scanner fixture"
      When call sbom.vuln_count "${FIX}/osv-scanner.cdx.json"
      The output should equal "1"
    End

    It "returns 0 when vulnerabilities field is absent"
      no_vulns_file() {
        local f
        f="$(mktemp /tmp/no-vulns.XXXXXX.json)"
        jq 'del(.vulnerabilities)' "${FIX}/osv-scanner.cdx.json" > "$f"
        sbom.vuln_count "$f"
        local rc=$?
        rm -f "$f"
        return $rc
      }
      When call no_vulns_file
      The output should equal "0"
    End
  End

  Describe "sbom.is_valid"
    It "validates the osv-scanner CycloneDX fixture as valid"
      When call sbom.is_valid "${FIX}/osv-scanner.cdx.json"
      The status should be success
    End

    It "rejects a JSON document that is not CycloneDX"
      bad_file() {
        local f
        f="$(mktemp /tmp/not-a-cdx.XXXXXX.json)"
        echo '{"foo":"bar"}' > "$f"
        sbom.is_valid "$f"
        local rc=$?
        rm -f "$f"
        return $rc
      }
      When call bad_file
      The status should equal 1
    End

    It "rejects a non-existent file"
      When call sbom.is_valid "${FIX}/missing.cdx.json"
      The status should equal 1
    End
  End

  Describe "sbom.merge"
    setup_merge() {
      MERGE_DIR="$(mktemp -d)"
      jq '.' "${FIX}/osv-scanner.cdx.json" > "${MERGE_DIR}/a.cdx.json"
      jq '
        .components = [{
          "bom-ref": "pkg:npm/lodash@4.17.10",
          "type": "library",
          "name": "lodash",
          "version": "4.17.10",
          "purl": "pkg:npm/lodash@4.17.10"
        }]
        | .vulnerabilities = []
      ' "${FIX}/osv-scanner.cdx.json" > "${MERGE_DIR}/b.cdx.json"
    }
    cleanup_merge() {
      rm -rf "$MERGE_DIR"
    }
    Before 'setup_merge'
    After 'cleanup_merge'

    It "produces a valid CycloneDX 1.5 file"
      run_merge() {
        sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/a.cdx.json" "${MERGE_DIR}/b.cdx.json"
        sbom.is_valid "${MERGE_DIR}/out.cdx.json"
      }
      When call run_merge
      The status should be success
    End

    It "unions distinct components (osv uuid + lodash)"
      run_merge_components() {
        sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/a.cdx.json" "${MERGE_DIR}/b.cdx.json"
        jq -c '.components | map(.name) | sort' "${MERGE_DIR}/out.cdx.json"
      }
      When call run_merge_components
      The output should equal '["lodash","uuid"]'
    End

    It "deduplicates components that share the same bom-ref"
      run_merge_dedup() {
        cp "${MERGE_DIR}/a.cdx.json" "${MERGE_DIR}/a2.cdx.json"
        sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/a.cdx.json" "${MERGE_DIR}/a2.cdx.json"
        sbom.component_count "${MERGE_DIR}/out.cdx.json"
      }
      When call run_merge_dedup
      The output should equal "1"
    End

    It "preserves vulnerabilities from inputs"
      run_merge_vulns() {
        sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/a.cdx.json" "${MERGE_DIR}/b.cdx.json"
        sbom.vuln_count "${MERGE_DIR}/out.cdx.json"
      }
      When call run_merge_vulns
      The output should equal "1"
    End

    It "is the identity when given a single input"
      run_merge_single() {
        sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/a.cdx.json"
        sbom.component_count "${MERGE_DIR}/out.cdx.json"
      }
      When call run_merge_single
      The output should equal "1"
    End

    It "fails when no inputs are provided"
      When call sbom.merge "${MERGE_DIR}/out.cdx.json"
      The status should equal 2
      The stderr should include "at least one input"
    End

    It "fails when an input does not exist"
      When call sbom.merge "${MERGE_DIR}/out.cdx.json" "${MERGE_DIR}/missing.cdx.json"
      The status should equal 1
      The stderr should include "does not exist"
    End
  End
End
