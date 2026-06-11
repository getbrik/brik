#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "transverse/findings/org_policy.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/findings/org_policy.sh"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  setup_env() {
    POLICY_DIR="$(mktemp -d)"
    POLICY_YAML="${POLICY_DIR}/brik-policy.yml"
    CACHE="${POLICY_DIR}/policy.cache.json"
    export BRIK_WORKSPACE="${POLICY_DIR}/workspace"
    mkdir -p "${BRIK_WORKSPACE}/brik-artifacts"
    export BRIK_PROJECT_NAME="python-complete"
    unset BRIK_POLICY_URL BRIK_POLICY_CACHE_PATH BRIK_FINDINGS_EXPIRING_SOON_DAYS
  }
  cleanup_env() {
    rm -rf "$POLICY_DIR"
    unset BRIK_WORKSPACE BRIK_PROJECT_NAME BRIK_POLICY_URL BRIK_POLICY_CACHE_PATH \
          BRIK_FINDINGS_EXPIRING_SOON_DAYS
  }
  Before 'setup_env'
  After 'cleanup_env'

  Describe "API surface"
    It "declares org_policy.load"
      When call declare -f org_policy.load
      The status should be success
      The output should not be blank
    End

    It "declares org_policy.is_active"
      When call declare -f org_policy.is_active
      The status should be success
      The output should not be blank
    End

    It "declares org_policy.cache_path"
      When call declare -f org_policy.cache_path
      The status should be success
      The output should not be blank
    End

    It "declares org_policy.expiring_soon"
      When call declare -f org_policy.expiring_soon
      The status should be success
      The output should not be blank
    End
  End

  Describe "org_policy.cache_path"
    It "defaults to BRIK_WORKSPACE/.brik-logs/policy.cache.json"
      When call org_policy.cache_path
      The output should equal "${BRIK_WORKSPACE}/.brik-logs/policy.cache.json"
    End

    It "honors BRIK_POLICY_CACHE_PATH override"
      override() {
        export BRIK_POLICY_CACHE_PATH="/tmp/custom.cache.json"
        org_policy.cache_path
      }
      When call override
      The output should equal "/tmp/custom.cache.json"
    End
  End

  Describe "org_policy.is_active"
    It "returns false when no BRIK_POLICY_URL is set and no cache exists"
      When call org_policy.is_active
      The status should be failure
    End

    It "returns true once a cache file exists at the configured path"
      seed_cache() {
        export BRIK_POLICY_CACHE_PATH="$CACHE"
        printf '%s' '{"cve_allowlist":[],"path_globs":[],"expiring_soon":[]}' > "$CACHE"
        org_policy.is_active
      }
      When call seed_cache
      The status should be success
    End
  End

  Describe "org_policy.load"
    Skip if "yq missing" yq_missing
    Skip if "jv missing" jv_missing

    write_policy() {
      cat > "$POLICY_YAML"
    }

    Describe "with a valid file:// policy"
      It "writes a compiled cache JSON"
        load_minimal() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-6100
      reason: "no upstream fix"
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL"
          test -f "$CACHE"
        }
        When call load_minimal
        The status should be success
      End

      It "compiles cve_allowlist as a flat array of CVE ids"
        load_cves() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-6100
      reason: "no fix"
      expires: 2099-12-31
    - id: CVE-2025-15366
      reason: "dev-only"
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -c '.cve_allowlist | sort' "$CACHE"
        }
        When call load_cves
        The output should equal '["CVE-2025-15366","CVE-2026-6100"]'
      End

      It "compiles path_globs with translated regex"
        load_paths() {
          write_policy <<'YAML'
allow:
  paths:
    - glob: "vendor/**"
      reason: "Third-party"
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -r '.path_globs[0].regex' "$CACHE"
        }
        When call load_paths
        # vendor/** -> ^vendor/.*$
        The output should equal '^vendor/.*$'
      End

      It "captures the policy URL and load timestamp"
        load_meta() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-0001
      reason: "x"
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -r '.url' "$CACHE"
        }
        When call load_meta
        The output should include "${POLICY_YAML}"
      End

      It "honors a preset override declared at the top level"
        load_preset() {
          write_policy <<'YAML'
preset: strict
allow:
  cve: []
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -r '.preset_override' "$CACHE"
        }
        When call load_preset
        The output should equal "strict"
      End
    End

    Describe "filtering"
      It "drops CVE entries whose projects[] does not include the active project"
        load_scoped() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-1000
      reason: "global"
      expires: 2099-12-31
    - id: CVE-2026-1001
      reason: "other-project only"
      expires: 2099-12-31
      projects: ["other-app"]
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -c '.cve_allowlist | sort' "$CACHE"
        }
        When call load_scoped
        The output should equal '["CVE-2026-1000"]'
      End

      It "keeps CVE entries whose projects[] includes the active project"
        load_kept() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-2000
      reason: "scoped to ours"
      expires: 2099-12-31
      projects: ["python-complete"]
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -c '.cve_allowlist' "$CACHE"
        }
        When call load_kept
        The output should equal '["CVE-2026-2000"]'
      End

      It "drops entries whose expires is in the past"
        load_expired() {
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2024-9999
      reason: "expired"
      expires: 2024-01-01
    - id: CVE-2026-3000
      reason: "still valid"
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
          jq -c '.cve_allowlist' "$CACHE"
        }
        When call load_expired
        The output should equal '["CVE-2026-3000"]'
      End
    End

    Describe "error handling"
      It "fails with BRIK_EXIT_CONFIG_ERROR when the URL is inaccessible"
        bad_url() {
          export BRIK_POLICY_URL="file:///does/not/exist/policy.yml"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL"
        }
        When call bad_url
        The status should equal 7
        The error should include "file://"
      End

      It "fails with BRIK_EXIT_CONFIG_ERROR when the YAML is malformed"
        bad_yaml() {
          printf 'preset: : invalid\n  allow: {' > "$POLICY_YAML"
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL"
        }
        When call bad_yaml
        The status should equal 7
        The error should include "file://"
      End

      It "fails with BRIK_EXIT_CONFIG_ERROR when the policy violates the schema"
        bad_schema() {
          # Missing required reason field on the CVE entry.
          write_policy <<'YAML'
allow:
  cve:
    - id: CVE-2026-9999
      expires: 2099-12-31
YAML
          export BRIK_POLICY_URL="file://${POLICY_YAML}"
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL"
        }
        When call bad_schema
        The status should equal 7
        The error should include "schema validation failed"
      End

      It "is a no-op when BRIK_POLICY_URL is unset"
        no_url() {
          unset BRIK_POLICY_URL
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          org_policy.load "$BRIK_POLICY_URL"
          test ! -f "$CACHE"
        }
        When call no_url
        The status should be success
      End
    End
  End

  Describe "org_policy.state_repo_protection"
    Skip if "yq missing" yq_missing
    Skip if "jv missing" jv_missing

    write_policy() {
      cat > "$POLICY_YAML"
    }

    It "echoes the declared posture"
      posture() {
        write_policy <<'YAML'
state_repo_protection: required
YAML
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call posture
      The output should equal "required"
    End

    It "defaults to warn when the policy does not set the field"
      posture() {
        write_policy <<'YAML'
preset: strict
YAML
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call posture
      The output should equal "warn"
    End

    It "fails closed on a value outside the enum (schema refusal)"
      posture() {
        write_policy <<'YAML'
state_repo_protection: maybe
YAML
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call posture
      The status should equal 7
      The stderr should include "schema"
    End

    It "fails closed when the policy is unreachable (a governed project must not regress silently)"
      When call org_policy.state_repo_protection "file:///does/not/exist/policy.yml"
      The status should equal 7
      The stderr should include "cannot fetch"
    End
  End

  Describe "org_policy.expiring_soon"
    Skip if "yq missing" yq_missing
    Skip if "jv missing" jv_missing

    write_policy() { cat > "$POLICY_YAML"; }

    It "lists entries whose expires falls within the lookback window (default 30 days)"
      seed_soon() {
        local soon7
        soon7="$(date -u -d '+7 days' +%Y-%m-%d 2>/dev/null \
                || date -u -v '+7d' +%Y-%m-%d 2>/dev/null \
                || date -u +%Y-%m-%d)"
        write_policy <<YAML
allow:
  cve:
    - id: CVE-2026-9001
      reason: "renew"
      expires: ${soon7}
    - id: CVE-2026-9002
      reason: "long-lived"
      expires: 2099-12-31
YAML
        export BRIK_POLICY_URL="file://${POLICY_YAML}"
        export BRIK_POLICY_CACHE_PATH="$CACHE"
        org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
        org_policy.expiring_soon | jq -r '.[].id' | sort
      }
      When call seed_soon
      The output should equal "CVE-2026-9001"
    End

    It "respects BRIK_FINDINGS_EXPIRING_SOON_DAYS override"
      seed_window() {
        local soon60
        soon60="$(date -u -d '+60 days' +%Y-%m-%d 2>/dev/null \
                || date -u -v '+60d' +%Y-%m-%d 2>/dev/null \
                || date -u +%Y-%m-%d)"
        write_policy <<YAML
allow:
  cve:
    - id: CVE-2026-9060
      reason: "x"
      expires: ${soon60}
YAML
        export BRIK_POLICY_URL="file://${POLICY_YAML}"
        export BRIK_POLICY_CACHE_PATH="$CACHE"
        org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
        # Default window 30 days excludes; bump to 90 to include.
        export BRIK_FINDINGS_EXPIRING_SOON_DAYS=90
        org_policy.expiring_soon | jq -r '.[].id'
      }
      When call seed_window
      The output should equal "CVE-2026-9060"
    End

    It "returns an empty array when no allowlist is loaded"
      no_load() {
        unset BRIK_POLICY_URL
        export BRIK_POLICY_CACHE_PATH="$CACHE"
        org_policy.expiring_soon
      }
      When call no_load
      The output should equal "[]"
      The status should be success
    End
  End
End
