#!/usr/bin/env bash
# @module report.fragment
# @requires jq
# @description Per-stage fragment writer and CI fragment aggregator.
#
# Split out of lib/pipeline/report.sh. write_fragment snapshots a single
# stage's backend entry into the v1.1 fragment envelope; aggregate_fragments
# merges per-stage fragment files (shipped as CI job artifacts) back into a
# single aggregate-report.{json,md,html}. Loaded by the report.sh facade.
#
# Cross-module calls resolved at runtime via the facade:
#   _report._render_aggregate_md  (report/render_md.sh)
#   _report._render_html          (report_html/render.sh)
#   sarif.extract_items           (transverse/sarif.sh)
#   registry.stage.list           (registry, optional -- guarded by declare -f)

[[ -n "${_BRIK_REPORT_FRAGMENT_LOADED:-}" ]] && return 0
_BRIK_REPORT_FRAGMENT_LOADED=1

# shellcheck source=../logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../logging.sh"
# shellcheck source=../error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../error.sh"
# shellcheck source=../../transverse/sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../../transverse/sarif.sh"

# Write a per-stage report fragment to brik-artifacts/<stage>.json so CI
# platforms (GitLab, Jenkins) can ship it as a job artifact and notify can
# aggregate fragments back into a single aggregate-report at the end.
#
# The fragment is a snapshot of the backend aggregate-report.json entry for
# this stage, wrapped in the v1 fragment envelope (schema_version, stage,
# timestamp, rc, status, runner). When the backend has no entry for this
# stage, the fragment is a stub with status=skipped, rc=0.
#
# Output path:
#   - ${BRIK_WORKSPACE}/brik-artifacts/<stage>/<stage>.json when BRIK_WORKSPACE is set
#   - ${BRIK_LOG_DIR}/brik-artifacts/<stage>/<stage>.json otherwise (local fallback)
#
# Runner provenance:
#   - platform := BRIK_PLATFORM (default: local)
#   - image    := BRIK_RUNNER_IMAGE (omitted when unset)
#   - job_url  := CI_JOB_URL (GitLab) or BUILD_URL (Jenkins), omitted when unset
#
# Usage: report.write_fragment <stage_name>
# Returns: 0 on success, BRIK_EXIT_INVALID_INPUT on bad args,
#          BRIK_EXIT_MISSING_DEP if jq is absent, BRIK_EXIT_IO_FAILURE on
#          backend missing or write failure.
#
# Note: the parameter is named `stage_name` rather than `stage` to avoid
# dynamic-scope shadowing of any caller's `stage` local variable (Bash
# locals are visible to callees through dynamic scope).
report.write_fragment() {
    if [[ $# -ne 1 ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.write_fragment expects 1 argument: stage (got $#)"
        return "$?"
    fi
    local stage_name="$1"
    if [[ -z "$stage_name" ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.write_fragment: stage name must not be empty"
        return "$?"
    fi

    _report._require_jq || return "$?"

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local fragment_dir="${BRIK_WORKSPACE:-$(_brik.log_dir._resolve)}/brik-artifacts"
    local stage_dir="${fragment_dir}/${stage_name}"
    mkdir -p "$stage_dir" || {
        log.error "cannot create fragment directory: $stage_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local fragment_path="${stage_dir}/${stage_name}.json"
    local timestamp
    timestamp="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local platform="${BRIK_PLATFORM:-local}"
    local image="${BRIK_RUNNER_IMAGE:-}"
    local job_url="${CI_JOB_URL:-${BUILD_URL:-}}"

    local tmp
    tmp="$(mktemp "${fragment_path}.XXXXXX")" || {
        log.error "cannot create temp fragment file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # KCOV_EXCL_START  -- jq script body is not bash code
    jq \
        --arg stage_name "$stage_name" \
        --arg timestamp "$timestamp" \
        --arg platform "$platform" \
        --arg image "$image" \
        --arg job_url "$job_url" \
        '
        ( [ .stages[] | select(.stage == $stage_name) ][0] // {} ) as $entry
        | ( $entry.tech     // {} ) as $tech
        | ( $entry.business // {} ) as $business
        | ( $entry.env      // {} ) as $env
        | ( $tech.status    // "skipped" ) as $status
        | ( ($tech.exit_code // 0) | tonumber? // 0 ) as $rc
        | ( $tech.duration_ms ) as $duration_raw
        # v1.1 requires business.status. When the stage did not write one
        # (legacy producer, stub fragment for a stage absent from the
        # backend, ...), default from tech.status: success/skipped map to
        # success, failed maps to error. _stage._record_business overrides
        # this for stages that ran through the matrix.
        | ( if ($business | type) == "object" and ($business | has("status"))
            then $business
            else $business + { status: ( if $status == "failed" then "error" else "success" end ) }
            end ) as $business_v11
        | ( {
            schema_version: "1.1",
            stage: $stage_name,
            timestamp: $timestamp,
            rc: $rc,
            status: $status,
            runner: ( { platform: $platform }
                      + ( if $image   != "" then { image:   $image   } else {} end )
                      + ( if $job_url != "" then { job_url: $job_url } else {} end ) ),
            tech: $tech,
            business: $business_v11
          }
          + ( if $duration_raw == null or $duration_raw == "" then {}
              else { duration_ms: ($duration_raw | tonumber? // 0) } end )
          + ( if ($env | length) > 0 then { env: $env } else {} end ) )
        ' "$backend" > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot build fragment for stage: $stage_name"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$fragment_path" || {
        rm -f "$tmp"
        log.error "cannot write fragment: $fragment_path"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    log.debug "fragment written: $fragment_path"
    return 0
}

# Aggregate per-stage fragment files into a single aggregate-report.{md,json}
# under $BRIK_LOG_DIR. Used by stages.notify in CI mode where each upstream
# stage runs in its own container and ships its fragment as a job artifact.
# In local mode this function is not called (pipeline.run already produces
# the aggregate directly via report.record + report.render).
#
# Filtering rules:
#   - <dir>/aggregate-report.json is ignored (it is the aggregate target).
#   - Files that are not valid JSON are silently skipped.
#   - Files lacking the fragment signature (.stage and .schema_version) are
#     silently skipped (forward-compat with arbitrary brik-artifacts/ content).
#   - Files with schema_version not in {"1.0","1.1"} are warn-and-skipped
#     (decision 7: forward-compat with future v2 fragments). v1.0 stays
#     readable through the chantier 11 transition window so archived
#     fragments and external producers keep aggregating cleanly while
#     they migrate; the runtime itself emits v1.1.
#
# Pipeline metadata sources (decision 5: env-first in v1):
#   - pipeline.id        := BRIK_RUN_ID
#   - pipeline.platform  := BRIK_PLATFORM (default "local")
#   - pipeline.project   := BRIK_PROJECT_NAME (default "unnamed")
#   - pipeline.started_at:= earliest fragment timestamp, or now when none
#   - pipeline.finished_at:= now
#   - pipeline.status    := "failed" if any stage failed, else "success"
#
# Usage: report.aggregate_fragments <dir>
# Returns: 0 on success, BRIK_EXIT_INVALID_INPUT on bad args,
#          BRIK_EXIT_MISSING_DEP if jq is absent, BRIK_EXIT_IO_FAILURE on
#          missing dir or write failure.
report.aggregate_fragments() {
    if [[ $# -ne 1 ]]; then
        if [[ $# -eq 0 ]]; then
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.aggregate_fragments expects 1 argument: directory (got 0)"
        else
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.aggregate_fragments expects 1 argument: directory (got $#)"
        fi
        return "$?"
    fi
    local fragment_dir="$1"
    if [[ ! -d "$fragment_dir" ]]; then
        log.error "fragment directory not found: $fragment_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    _report._require_jq || return "$?"

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Collect valid fragment paths into a tmp index file.
    local valid_list
    valid_list="$(mktemp)" || {
        log.error "cannot create temp index"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    shopt -s nullglob
    local f base sv
    for f in "$fragment_dir"/*/*.json; do
        base="$(basename "$f")"
        # Ignore the aggregate output if it lives in the same directory.
        [[ "$base" == "aggregate-report.json" ]] && continue
        # Must be valid JSON object with the fragment signature.
        if ! jq -e 'type == "object" and has("stage") and has("schema_version")' \
                "$f" >/dev/null 2>&1; then
            continue
        fi
        # Schema version gate: warn-and-skip on mismatch.
        sv="$(jq -r '.schema_version' "$f" 2>/dev/null)"
        case "$sv" in
            1.0|1.1) ;;
            *)
                log.warn "fragment ${base}: unsupported schema_version '${sv}' (expected '1.0' or '1.1'), skipping"
                continue
                ;;
        esac
        printf '%s\n' "$f" >> "$valid_list"
    done
    shopt -u nullglob

    local pipeline_id="${BRIK_PIPELINE_ID:-${BRIK_RUN_ID:-$(date +%s)-$$}}"
    local platform="${BRIK_PLATFORM:-local}"
    local project="${BRIK_PROJECT_NAME:-unnamed}"
    local finished_at
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local pipeline_context="snapshot"
    [[ -n "${BRIK_COMMIT_TAG:-}" ]] && pipeline_context="release"

    # Findings policy projection (chantier 20260508 P1.5 / P3.F). The active
    # built-in preset comes from BRIK_QUALITY_FINDINGS_POLICY (export config
    # flow), with pragmatic as the documented default. P3 layers the org
    # policy cache on top: a non-null preset_override in the cache wins over
    # the project preset and flips source to "org-policy". The cache also
    # carries url + loaded_at + expiring_soon entries that surface alongside
    # the active preset for the operator.
    local policy_preset="${BRIK_QUALITY_FINDINGS_POLICY:-pragmatic}"
    local policy_source="brik.yml"
    local policy_org_url=""
    local policy_org_loaded_at=""
    local policy_expiring_soon='[]'

    local _policy_cache="${BRIK_POLICY_CACHE_PATH:-${BRIK_WORKSPACE:-/tmp/brik}/.brik-logs/policy.cache.json}"
    if [[ -f "$_policy_cache" ]] && command -v jq >/dev/null 2>&1; then
        local _override
        _override="$(jq -r '.preset_override // empty' "$_policy_cache" 2>/dev/null)"
        if [[ -n "$_override" ]]; then
            policy_preset="$_override"
            policy_source="org-policy"
        fi
        policy_org_url="$(jq -r '.url // empty' "$_policy_cache" 2>/dev/null)"
        policy_org_loaded_at="$(jq -r '.loaded_at // empty' "$_policy_cache" 2>/dev/null)"

        # Compute expiring_soon entries inline. Lookback window defaults to
        # 30 days and respects the BRIK_FINDINGS_EXPIRING_SOON_DAYS override.
        local _days="${BRIK_FINDINGS_EXPIRING_SOON_DAYS:-30}"
        local _now _soon_epoch _soon_date
        _now="$(date -u +%s)"
        _soon_epoch=$((_now + _days * 86400))
        _soon_date="$(date -u -d "@${_soon_epoch}" +%Y-%m-%d 2>/dev/null \
                   || date -u -r "${_soon_epoch}" +%Y-%m-%d 2>/dev/null \
                   || date -u +%Y-%m-%d)"
        # KCOV_EXCL_START -- jq script body is not bash code
        policy_expiring_soon="$(jq -c --arg soon "$_soon_date" '
            [
              (.cve_entries // [])[]
              | select(.expires <= $soon)
              | { type: "cve", id: .id, expires: .expires, reason: (.reason // "") }
            ]
            +
            [
              (.path_entries // [])[]
              | select(.expires <= $soon)
              | { type: "path", glob: .glob, expires: .expires, reason: (.reason // "") }
            ]
        ' "$_policy_cache" 2>/dev/null || printf '[]')"
        # KCOV_EXCL_STOP
    fi

    # Optional pipeline metadata: surface only when the source variable is
    # set, so the aggregate omits absent fields rather than emitting empty
    # strings (matches schema 'optional' semantics).
    local pipeline_url="${BRIK_PIPELINE_URL:-}"
    local dry_run="false"
    [[ "${BRIK_DRY_RUN:-}" == "true" ]] && dry_run="true"
    local commit_sha="${BRIK_COMMIT_SHA:-}"
    local commit_short_sha="${BRIK_COMMIT_SHORT_SHA:-}"
    local commit_ref="${BRIK_COMMIT_REF:-}"
    local commit_branch="${BRIK_COMMIT_BRANCH:-}"
    local commit_tag="${BRIK_COMMIT_TAG:-}"
    local commit_author="${BRIK_COMMIT_AUTHOR:-}"
    local commit_author_email="${BRIK_COMMIT_AUTHOR_EMAIL:-}"
    local commit_timestamp="${BRIK_COMMIT_TIMESTAMP:-}"
    local commit_message_subject="${BRIK_COMMIT_MESSAGE_SUBJECT:-}"
    local commit_repo_url="${BRIK_COMMIT_REPO_URL:-}"
    local triggered_by="${BRIK_TRIGGERED_BY:-}"

    local backend="${log_dir}/aggregate-report.json"
    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || {
        rm -f "$valid_list"
        log.error "cannot create temp aggregate file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Build a JSON array of valid fragments. Read paths into an array so
    # word-splitting is explicit (filenames with spaces stay safe) and the
    # static analyser stays quiet.
    local frags_json
    local -a frag_paths=()
    if [[ -s "$valid_list" ]]; then
        local _line
        while IFS= read -r _line; do
            [[ -n "$_line" ]] && frag_paths+=("$_line")
        done < "$valid_list"
    fi
    rm -f "$valid_list"

    if (( ${#frag_paths[@]} > 0 )); then
        frags_json="$(jq -s '.' "${frag_paths[@]}")" || {
            rm -f "$tmp"
            log.error "cannot read valid fragments"
            return "$BRIK_EXIT_IO_FAILURE"
        }
    else
        frags_json='[]'
    fi

    # Note: the synthetic skip-fragments branch (Lot 2 of chantier
    # 20260526) was removed in Lot 5 because every stage now produces a
    # fragment on disk -- either via the plan-gate (run or skip) or via
    # the stage body. GitLab's .brik-stage template sources the gate as
    # the first script step; the Jenkins brikDriver loop calls
    # `brik plan gate` for every stage in the registry list. So `$frags`
    # is already complete; no synthesis needed.

    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -n \
        --arg pid "$pipeline_id" \
        --arg platform "$platform" \
        --arg project "$project" \
        --arg context "$pipeline_context" \
        --arg finished_at "$finished_at" \
        --arg pipeline_url "$pipeline_url" \
        --arg commit_sha "$commit_sha" \
        --arg commit_short_sha "$commit_short_sha" \
        --arg commit_ref "$commit_ref" \
        --arg commit_branch "$commit_branch" \
        --arg commit_tag "$commit_tag" \
        --arg commit_author "$commit_author" \
        --arg commit_author_email "$commit_author_email" \
        --arg commit_timestamp "$commit_timestamp" \
        --arg commit_message_subject "$commit_message_subject" \
        --arg commit_repo_url "$commit_repo_url" \
        --arg triggered_by "$triggered_by" \
        --arg policy_preset "$policy_preset" \
        --arg policy_source "$policy_source" \
        --arg policy_org_url "$policy_org_url" \
        --arg policy_org_loaded_at "$policy_org_loaded_at" \
        --argjson policy_expiring_soon "$policy_expiring_soon" \
        --arg dry_run "$dry_run" \
        --argjson frags "$frags_json" \
        '
        ( $frags
          | map(.timestamp // null)
          | map(select(. != null))
          | sort
          | .[0] // $finished_at ) as $started
        | ( $frags | map(.status)
          | { total: length,
              passed:  map(select(. == "success")) | length,
              failed:  map(select(. == "failed"))  | length,
              skipped: map(select(. == "skipped")) | length } ) as $counts
        | ( $frags | map(.business.status // "success")
          | { success_count: map(select(. == "success")) | length,
              warning_count: map(select(. == "warning")) | length,
              error_count:   map(select(. == "error"))   | length } ) as $business_summary
        | ( if ($business_summary.error_count // 0)   > 0 then "error"
            elif ($business_summary.warning_count // 0) > 0 then "warning"
            else "success" end ) as $pipeline_business_status
        | ( if ($counts.failed // 0) > 0 then "failed" else "success" end ) as $pstatus
        | ( { preset: $policy_preset, source: $policy_source }
            + ( if $policy_org_url       != "" then { org_policy_url:       $policy_org_url       } else {} end )
            + ( if $policy_org_loaded_at != "" then { org_policy_loaded_at: $policy_org_loaded_at } else {} end )
            + ( if ($policy_expiring_soon | length) > 0 then { expiring_soon: $policy_expiring_soon } else {} end )
          ) as $policy
        | ( {}
            + ( if $commit_sha             != "" then { sha:             $commit_sha             } else {} end )
            + ( if $commit_short_sha       != "" then { short_sha:       $commit_short_sha       } else {} end )
            + ( if $commit_ref             != "" then { ref:             $commit_ref             } else {} end )
            + ( if $commit_branch          != "" then { branch:          $commit_branch          } else {} end )
            + ( if $commit_tag             != "" then { tag:             $commit_tag             } else {} end )
            + ( if $commit_author          != "" then { author:          $commit_author          } else {} end )
            + ( if $commit_author_email    != "" then { author_email:    $commit_author_email    } else {} end )
            + ( if $commit_timestamp       != "" then { timestamp:       $commit_timestamp       } else {} end )
            + ( if $commit_message_subject != "" then { message_subject: $commit_message_subject } else {} end )
            + ( if $commit_repo_url        != "" then { repo_url:        $commit_repo_url        } else {} end )
          ) as $commit
        | ( {
              id: $pid,
              platform: $platform,
              project: $project,
              context: $context,
              business: { status: $pipeline_business_status },
              started_at: $started,
              finished_at: $finished_at,
              status: $pstatus
            }
            + ( if $pipeline_url != "" then { url:          $pipeline_url } else {} end )
            + ( if ($commit | length) > 0 then { commit:    $commit       } else {} end )
            + ( if $triggered_by != "" then { triggered_by: $triggered_by } else {} end )
            + ( if $dry_run == "true" then { tech: { dry_run: true } } else {} end )
          ) as $pipeline
        | {
            schema_version: "1.1",
            pipeline: $pipeline,
            stages: $frags,
            summary: {
              stages: $counts,
              business: $business_summary,
              policy: $policy
            }
          }
        ' > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot build aggregate JSON"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$backend" || {
        rm -f "$tmp"
        log.error "cannot write aggregate report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Inline per-stage SARIF findings into business.findings.items so the
    # aggregate document is self-sufficient for HTML/MD consumers (no need
    # to fetch the SARIF separately). Non-fatal: a missing or malformed
    # SARIF leaves the stage unchanged.
    _report._enrich_findings_items "$backend" "$fragment_dir" 2>/dev/null || \
        log.warn "could not enrich findings.items (non-fatal)"

    # Render the markdown alongside the JSON. Use the aggregate-shape
    # renderer because the aggregate document differs from the local
    # backend (.pipeline.id vs .pipeline_id, .stages[].stage vs .name,
    # status/rc at fragment level vs nested under tech).
    _report._render_aggregate_md "$backend" > "${log_dir}/aggregate-report.md" 2>/dev/null || \
        log.warn "could not render aggregate-report.md (non-fatal)"

    # Render the self-contained HTML view alongside the JSON + MD. Operators
    # open this in a browser to drill into findings without leaving the
    # archived CI artefact bundle. Non-fatal on failure.
    _report._render_html "$backend" > "${log_dir}/aggregate-report.html" 2>/dev/null || \
        log.warn "could not render aggregate-report.html (non-fatal)"

    log.debug "aggregate report written: $backend"
    return 0
}

# Walk each stage in the aggregate JSON, find SARIF references inside its
# business payload (any nested object shaped {format: "sarif", path: ...}),
# load each SARIF via sarif.extract_items, and inject the union as
# business.findings.items. Stages with zero referenced SARIFs (or where
# every referenced file is missing) are left untouched, preserving the
# additive contract documented on the aggregate schema.
_report._enrich_findings_items() {
    local backend="$1" fragment_dir="$2"
    [[ -f "$backend" ]] || return 0

    local workspace="${BRIK_WORKSPACE:-$(dirname "$fragment_dir")}"
    local stage_count
    stage_count="$(jq -r '.stages | length' "$backend" 2>/dev/null)" || return 0
    [[ "$stage_count" =~ ^[0-9]+$ ]] || return 0
    (( stage_count > 0 )) || return 0

    local i=0
    while (( i < stage_count )); do
        # Collect SARIF paths declared in this stage's business (any nesting).
        local paths_json
        paths_json="$(jq -c --argjson i "$i" '
            .stages[$i].business // {}
            | [.. | objects | select(.format? == "sarif") | .path? // empty]
            | unique
        ' "$backend" 2>/dev/null)" || { i=$((i + 1)); continue; }

        # Skip stage when no SARIF refs.
        local paths_count
        paths_count="$(printf '%s' "$paths_json" | jq -r 'length' 2>/dev/null)"
        [[ "$paths_count" =~ ^[0-9]+$ ]] || paths_count=0
        if (( paths_count == 0 )); then
            i=$((i + 1))
            continue
        fi

        # Walk paths, accumulate items from existing SARIFs only.
        local items_json='[]'
        local p_idx=0
        while (( p_idx < paths_count )); do
            local rel_path
            rel_path="$(printf '%s' "$paths_json" | jq -r --argjson k "$p_idx" '.[$k]')"
            p_idx=$((p_idx + 1))
            [[ -z "$rel_path" || "$rel_path" == "null" ]] && continue
            local abs_path="${workspace}/${rel_path}"
            [[ -f "$abs_path" ]] || continue
            local one
            one="$(sarif.extract_items "$abs_path" 2>/dev/null)" || continue
            [[ -n "$one" ]] || continue
            items_json="$(printf '%s\n%s' "$items_json" "$one" \
                | jq -cs 'add')" || items_json='[]'
        done

        local items_len
        items_len="$(printf '%s' "$items_json" | jq -r 'length' 2>/dev/null)"
        [[ "$items_len" =~ ^[0-9]+$ ]] || items_len=0
        if (( items_len == 0 )); then
            i=$((i + 1))
            continue
        fi

        # Merge items into stage business.findings.items via temp file.
        local tmp
        tmp="$(mktemp "${backend}.enrich.XXXXXX")" || { i=$((i + 1)); continue; }
        if jq -c --argjson i "$i" --argjson items "$items_json" '
              .stages[$i].business.findings = ((.stages[$i].business.findings // {}) + {items: $items})
            ' "$backend" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$backend" || rm -f "$tmp"
        else
            rm -f "$tmp"
        fi

        i=$((i + 1))
    done
    return 0
}

# Emit the canonical stage execution order as a single space-separated line.
# The registry (registry.stage.list) is the single source of truth and is
# preferred whenever the module is loaded; otherwise the documented fixed
# flow is used as a fallback so report rendering stays self-contained when
# invoked without the registry (e.g. standalone unit tests, CI stage jobs
# that did not source the registry).
_report._stage_order() {
    if declare -f registry.stage.list >/dev/null 2>&1; then
        local _ids
        if _ids="$(registry.stage.list 2>/dev/null)" && [[ -n "$_ids" ]]; then
            printf '%s' "$_ids" | tr '\n' ' '
            return 0
        fi
    fi
    printf '%s' "init release build lint sast scan test package container-scan promote deploy notify"
}
