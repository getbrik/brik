#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "transverse/findings/org_policy.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/findings/org_policy.sh"

  # Run <fn> with only <keep...> resolvable on PATH (essential coreutils plus
  # the named tools), so dependency-probe branches can be exercised in-process.
  with_only_tools() {
    local keep_csv="$1"; shift
    local sandbox; sandbox="$(mktemp -d)"
    local cmd path
    for cmd in mktemp mkdir rm cat printf date dirname sed grep ${keep_csv//,/ }; do
      path="$(command -v "$cmd" 2>/dev/null)" && [[ -n "$path" ]] \
        && ln -sf "$path" "${sandbox}/${cmd}"
    done
    local saved="$PATH" rc=0
    PATH="$sandbox"
    "$@"
    rc=$?
    PATH="$saved"
    rm -rf "$sandbox"
    return $rc
  }

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

  Describe "_org_policy._glob_to_regex"
    Parameters
      "src/*"        '^src/[^/]*$'
      "src/?.txt"    '^src/[^/]\.txt$'
      "a.b+c"        '^a\.b\+c$'
      "lib/[gen]/x"  '^lib/\[gen\]/x$'
      "a/**/b"       '^a/.*/b$'
    End
    It "translates glob $1 to anchored regex $2"
      When call _org_policy._glob_to_regex "$1"
      The output should equal "$2"
    End
  End

  Describe "_org_policy._epoch_to_date"
    It "renders an epoch as a UTC ISO date"
      # 1700000000 == 2023-11-14 (UTC) on both GNU and BSD date.
      When call _org_policy._epoch_to_date 1700000000
      The output should equal "2023-11-14"
    End
  End

  Describe "org_policy.load"
    Skip if "yq missing" yq_missing
    Skip if "jv missing" jv_missing

    write_policy() {
      cat > "$POLICY_YAML"
    }

    It "fails with BRIK_EXIT_IO_FAILURE when the cache directory cannot be created"
      blocked_dir() {
        # A regular file where org_policy.load needs a directory makes
        # mkdir -p fail (the parent of .brik-logs is a file, not a dir).
        printf 'x' > "${POLICY_DIR}/blocker"
        export BRIK_POLICY_CACHE_PATH="${POLICY_DIR}/blocker/.brik-logs/policy.cache.json"
        write_policy <<'YAML'
allow:
  cve: []
YAML
        export BRIK_POLICY_URL="file://${POLICY_YAML}"
        org_policy.load "$BRIK_POLICY_URL"
      }
      When call blocked_dir
      The status should equal 6
      The stderr should include "cannot create cache directory"
    End

    It "fails with BRIK_EXIT_IO_FAILURE when the cache tmp file cannot be created"
      readonly_dir() {
        # The cache dir already exists (mkdir -p is a no-op) but is read-only,
        # so mktemp "$cache.XXXXXX" inside it fails -- the tmp-file branch.
        mkdir -p "${POLICY_DIR}/ro"
        chmod 0555 "${POLICY_DIR}/ro"
        export BRIK_POLICY_CACHE_PATH="${POLICY_DIR}/ro/policy.cache.json"
        write_policy <<'YAML'
allow:
  cve: []
YAML
        export BRIK_POLICY_URL="file://${POLICY_YAML}"
        org_policy.load "$BRIK_POLICY_URL"
        local rc=$?
        chmod 0755 "${POLICY_DIR}/ro"
        return $rc
      }
      When call readonly_dir
      The status should equal 6
      The stderr should include "cannot create cache tmp file"
    End

    It "compiles regex for several path globs in one policy"
      load_many_paths() {
        write_policy <<'YAML'
allow:
  paths:
    - glob: "src/*"
      reason: "single segment"
      expires: 2099-12-31
    - glob: "vendor/**"
      reason: "subtree"
      expires: 2099-12-31
YAML
        export BRIK_POLICY_URL="file://${POLICY_YAML}"
        export BRIK_POLICY_CACHE_PATH="$CACHE"
        org_policy.load "$BRIK_POLICY_URL" >/dev/null 2>&1
        jq -r '.path_globs | length' "$CACHE"
      }
      When call load_many_paths
      The output should equal "2"
    End

    Describe "missing dependencies"
      It "fails with BRIK_EXIT_MISSING_DEP when curl is unavailable"
        no_curl() {
          write_policy <<'YAML'
allow:
  cve: []
YAML
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          # yq and jq resolvable, curl deliberately absent.
          with_only_tools "yq,jq" org_policy.load "file://${POLICY_YAML}"
        }
        When call no_curl
        The status should equal 3
        The stderr should include "curl not on PATH"
      End

      It "fails with BRIK_EXIT_MISSING_DEP when yq is unavailable"
        no_yq() {
          write_policy <<'YAML'
allow:
  cve: []
YAML
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          with_only_tools "curl,jq" org_policy.load "file://${POLICY_YAML}"
        }
        When call no_yq
        The status should equal 3
        The stderr should include "yq not on PATH"
      End

      It "fails with BRIK_EXIT_MISSING_DEP when jq is unavailable"
        no_jq() {
          write_policy <<'YAML'
allow:
  cve: []
YAML
          export BRIK_POLICY_CACHE_PATH="$CACHE"
          with_only_tools "curl,yq" org_policy.load "file://${POLICY_YAML}"
        }
        When call no_jq
        The status should equal 3
        The stderr should include "jq not on PATH"
      End
    End

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

    It "echoes the off posture when declared"
      posture() {
        write_policy <<'YAML'
state_repo_protection: off
YAML
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call posture
      The output should equal "off"
    End

    It "requires a url (BRIK_EXIT_INVALID_INPUT)"
      When call org_policy.state_repo_protection ""
      The status should equal 2
      The stderr should include "<url> is required"
    End

    It "fails closed on malformed YAML"
      bad_yaml() {
        printf 'state_repo_protection: : oops\n  nested: {' > "$POLICY_YAML"
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call bad_yaml
      The status should equal 7
      The stderr should include "malformed YAML"
    End

    It "fails closed on a value outside the enum (bash enforcement)"
      bad_value() {
        # A syntactically valid policy whose value is rejected by the bash
        # enum guard (exercises the default case independently of the schema).
        printf 'state_repo_protection: loose\n' > "$POLICY_YAML"
        org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call bad_value
      The status should equal 7
      The stderr should include "violates the policy schema"
    End

    It "fails closed when the policy is unreachable (a governed project must not regress silently)"
      When call org_policy.state_repo_protection "file:///does/not/exist/policy.yml"
      The status should equal 7
      The stderr should include "cannot fetch"
    End

    It "fails with BRIK_EXIT_MISSING_DEP when a dependency is unavailable"
      no_jq() {
        write_policy <<'YAML'
state_repo_protection: required
YAML
        with_only_tools "curl,yq" \
          org_policy.state_repo_protection "file://${POLICY_YAML}"
      }
      When call no_jq
      The status should equal 3
      The stderr should include "jq not on PATH"
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
