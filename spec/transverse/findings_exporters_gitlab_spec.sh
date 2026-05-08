#shellcheck shell=bash
# Tests for the GitLab gl-sast-report.json exporter (chantier 20260508 P6.D).

Describe "transverse/findings/exporters/gitlab.sh"
  Include "$BRIK_HOME/lib/transverse/findings/exporters/gitlab.sh"

  setup_export() {
    OUT="$(mktemp).json"
    SARIF="$(mktemp).sarif"
  }
  cleanup_export() { rm -f "$OUT" "$SARIF"; }
  Before 'setup_export'
  After  'cleanup_export'

  # Synthetic SARIF mirroring a grype-like shape: rule-level CVSS,
  # CVE-shaped ruleId, one suppressed result that must be skipped.
  write_grype_sarif() {
    cat > "$SARIF" <<'JSON'
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "grype",
          "rules": [
            { "id": "CVE-2026-9001", "shortDescription": {"text": "synthetic critical"},
              "properties": {"security-severity": "9.1", "tags": ["CWE-787"]} },
            { "id": "CVE-2026-9002", "shortDescription": {"text": "synthetic high"},
              "properties": {"security-severity": "7.5"} },
            { "id": "CVE-2026-9003", "shortDescription": {"text": "synthetic medium suppressed"},
              "properties": {"security-severity": "5.5"} }
          ]
        }
      },
      "results": [
        {
          "ruleId": "CVE-2026-9001",
          "level": "error",
          "message": {"text": "Critical CVE in lib"},
          "locations": [{
            "physicalLocation": {
              "artifactLocation": {"uri": "src/lib.py"},
              "region": {"startLine": 12, "endLine": 12}
            }
          }],
          "partialFingerprints": {"primaryLocationLineHash": "abc123:1"}
        },
        {
          "ruleId": "CVE-2026-9002",
          "level": "error",
          "message": {"text": "High CVE"},
          "locations": [{
            "physicalLocation": {
              "artifactLocation": {"uri": "src/api.py"},
              "region": {"startLine": 5, "endLine": 5}
            }
          }]
        },
        {
          "ruleId": "CVE-2026-9003",
          "level": "warning",
          "message": {"text": "Suppressed by policy"},
          "locations": [{"physicalLocation": {"artifactLocation": {"uri": "src/x.py"}, "region": {"startLine": 1}}}],
          "suppressions": [{
            "kind": "external",
            "justification": "Brik policy: below-severity",
            "properties": {"brikSource": "policy.built-in.below-severity"}
          }]
        }
      ]
    }
  ]
}
JSON
  }

  Describe "from_sarif"
    setup_grype() { write_grype_sarif; }
    Before 'setup_grype'

    It "produces a gl-sast-report v15.0.0 envelope"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '"\(.version) \(.scan.type) \(.scan.scanner.name)"' "$OUT"
      }
      When call run
      The output should equal "15.0.0 sast Brik"
    End

    It "emits one vulnerability per failing result and skips suppressed ones"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '.vulnerabilities | length' "$OUT"
      }
      When call run
      The output should equal "2"
    End

    It "maps CVSS 9.1 to Critical and CVSS 7.5 to High"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -c '[.vulnerabilities[] | {id: .cve, sev: .severity}] | sort_by(.id)' "$OUT"
      }
      When call run
      The output should include '{"id":"CVE-2026-9001","sev":"Critical"}'
      The output should include '{"id":"CVE-2026-9002","sev":"High"}'
    End

    It "carries CVE-shaped ruleIds into the cve field"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '[.vulnerabilities[].cve] | sort | .[]' "$OUT"
      }
      When call run
      The output should include "CVE-2026-9001"
      The output should include "CVE-2026-9002"
    End

    It "translates rule.properties.tags CWE-NN into identifiers"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '.vulnerabilities[] | select(.cve == "CVE-2026-9001") | .identifiers[] | select(.type == "cwe") | "\(.name) \(.url)"' "$OUT"
      }
      When call run
      The output should include "CWE-787"
      The output should include "https://cwe.mitre.org/data/definitions/787.html"
    End

    It "uses partialFingerprints.primaryLocationLineHash as vulnerability id when present"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '.vulnerabilities[] | select(.cve == "CVE-2026-9001") | .id' "$OUT"
      }
      When call run
      The output should equal "abc123:1"
    End

    It "falls back to a stable composite id when no fingerprint is set"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '.vulnerabilities[] | select(.cve == "CVE-2026-9002") | .id' "$OUT"
      }
      When call run
      The output should include "grype|CVE-2026-9002|src/api.py|5"
    End

    It "preserves location file + start_line"
      run() {
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -c '.vulnerabilities[] | select(.cve == "CVE-2026-9001") | .location' "$OUT"
      }
      When call run
      The output should include '"file":"src/lib.py"'
      The output should include '"start_line":12'
    End

    It "handles an empty SARIF aggregate cleanly"
      run() {
        printf '%s' '{"version":"2.1.0","runs":[]}' > "$SARIF"
        findings.exporters.gitlab.from_sarif "$SARIF" "$OUT" >/dev/null
        jq -r '.vulnerabilities | length' "$OUT"
      }
      When call run
      The output should equal "0"
    End

    It "rejects missing arguments"
      When call findings.exporters.gitlab.from_sarif
      The status should not be success
      The error should include "missing arguments"
    End

    It "fails IO when input is missing"
      When call findings.exporters.gitlab.from_sarif "/nonexistent.sarif" "$OUT"
      The status should not be success
      The error should include "input not found"
    End
  End
End
