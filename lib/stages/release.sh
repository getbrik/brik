#!/usr/bin/env bash
# @module stages/release
# @description Release stage - semantic version calculation + optional changelog and tag.

# Release stage: compute version from git tags, optionally generate changelog and tag.
# Usage: stages.release <context_file>
stages.release() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (app_version now lands in the pipeline report's business
    # section via report.record; cross-stage sharing via pipeline.env.set).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_release_vars

    # SC20: honour release.trigger.{on-tag, on-main, manual}. When the
    # block is absent in brik.yml, gating.should_run_stage returns 0
    # (legacy always-run). When present and no flag matches the current
    # pipeline context, mark the stage skipped + not-applicable so
    # business.evaluate yields success and downstream stages keep
    # running. Defensive: a test harness that stubs brik.use as a no-op
    # leaves gating.should_run_stage undefined; treat that as "run".
    brik.use transverse.gating 2>/dev/null || true
    if declare -f gating.should_run_stage >/dev/null 2>&1; then
        if ! gating.should_run_stage RELEASE; then
            log.info "release stage skipped: trigger conditions not met"
            report.record "release" "tech" "status" "skipped"   2>/dev/null || true
            report.record "release" "tech" "kind"   "not-applicable" 2>/dev/null || true
            return 0
        fi
    fi

    log.info "release stage - computing version"

    brik.use version
    brik.use git

    local strategy="${BRIK_RELEASE_STRATEGY:-semver}"
    local tag_prefix="${BRIK_RELEASE_TAG_PREFIX:-v}"

    log.info "release strategy: $strategy, tag prefix: $tag_prefix"

    report.record "release" "tech" "strategy" "$strategy" 2>/dev/null || true
    report.record "release" "tech" "tag_prefix" "$tag_prefix" 2>/dev/null || true
    local _dry_run_bool="false"
    [[ "${BRIK_DRY_RUN:-}" == "true" ]] && _dry_run_bool="true"
    report.record_object "release" "tech" "dry_run" "$_dry_run_bool" 2>/dev/null || true

    # When BRIK_TAG is set (CI_COMMIT_TAG on GitLab, TAG_NAME or explicit
    # BRIK_TAG parameter on Jenkins), use it as the source of truth for
    # the version. Without this, brik falls back to `git describe --tags`
    # which Jenkins Multibranch tag-scan checkouts return as
    # "origin/v0.2.0" instead of "v0.2.0" -- a name that contains a slash
    # and is rejected by Docker as an invalid image tag. BRIK_TAG carries
    # the platform's normalized tag intent and matches the configured tag
    # prefix, so prefer it whenever present.
    local current_version
    if [[ -n "${BRIK_TAG:-}" ]]; then
        current_version="${BRIK_TAG#"$tag_prefix"}"
        log.info "using BRIK_TAG as version source"
    else
        current_version="$(version.current --from-git-tag --prefix "$tag_prefix")" || {
            log.info "no git tag found, using 0.0.0"
            current_version="0.0.0"
        }
    fi

    log.info "current version: $current_version"
    export BRIK_APP_VERSION="$current_version"
    # No bump engine yet; previous_version and new_version stay equal until
    # a real version.next call lands. bump_type captures whether a release
    # was driven by an explicit BRIK_TAG or no bump at all (chantier
    # 20260502 L2.C.1, open question 2).
    report.record "release" "business" "previous_version" "$current_version" 2>/dev/null || true
    report.record "release" "business" "new_version" "$current_version" 2>/dev/null || true
    local _bump_type="none"
    [[ -n "${BRIK_TAG:-}" ]] && _bump_type="explicit"
    report.record "release" "business" "bump_type" "$_bump_type" 2>/dev/null || true
    pipeline.env.set "BRIK_APP_VERSION" "$current_version"

    # If on a tag (release trigger), prepare and finalize. A failure in either
    # step must propagate so the pipeline (and aggregate-report.json) reflect
    # the real outcome instead of the previous warn-and-return-0 behaviour.
    if [[ -n "${BRIK_TAG:-}" ]]; then
        _stages.release._prepare "$current_version" || return $?
        _stages.release._finalize "$current_version" "$tag_prefix" || return $?
    fi

    return 0
}

# Prepare a release: generate changelog, patch package.json, create commit.
_stages.release._prepare() {
    local version="$1"
    local changelog_enabled="${BRIK_RELEASE_CHANGELOG_ENABLED:-true}"
    local changelog_file="${BRIK_RELEASE_CHANGELOG_FILE:-CHANGELOG.md}"
    local dry_run="${BRIK_DRY_RUN:-}"

    if [[ "$changelog_file" != /* ]]; then
        changelog_file="${BRIK_WORKSPACE:-.}/${changelog_file}"
    fi

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        [[ "$changelog_enabled" == "true" ]] && log.info "[dry-run] changelog.generate > $changelog_file"
        log.info "[dry-run] patch package.json version to $version (if present)"
        log.info "[dry-run] git add -A + commit 'release: $version'"
        log.info "release prepared (dry-run): $version"
        return 0
    fi

    # Re-trigger detection: if the version's tag already points at HEAD,
    # the release was prepared and finalized on a previous run. Treat
    # _prepare as a no-op so we don't create a new commit (which would
    # advance HEAD and invalidate the existing tag).
    local tag_prefix="${BRIK_RELEASE_TAG_PREFIX:-v}"
    if git -C "${BRIK_WORKSPACE:-.}" rev-parse --verify --quiet "refs/tags/${tag_prefix}${version}" >/dev/null 2>&1; then
        local tag_sha head_sha
        tag_sha="$(git -C "${BRIK_WORKSPACE:-.}" rev-parse "refs/tags/${tag_prefix}${version}^{commit}" 2>/dev/null)"
        head_sha="$(git -C "${BRIK_WORKSPACE:-.}" rev-parse HEAD 2>/dev/null)"
        if [[ -n "$tag_sha" && "$tag_sha" == "$head_sha" ]]; then
            log.info "release ${version} already prepared (tag at HEAD); skipping prepare"
            return 0
        fi
    fi

    if [[ "$changelog_enabled" == "true" ]]; then
        brik.use changelog
        log.info "generating changelog to $changelog_file"
        local changelog_content
        changelog_content="$(changelog.generate)" || return $?

        if [[ -f "$changelog_file" ]]; then
            local tmp
            tmp="$(mktemp)" || return "$BRIK_EXIT_IO_FAILURE"
            {
                printf '# %s\n\n' "$version"
                printf '%s\n\n' "$changelog_content"
                cat "$changelog_file"
            } > "$tmp"
            mv "$tmp" "$changelog_file" || return "$BRIK_EXIT_IO_FAILURE"
        else
            {
                printf '# %s\n\n' "$version"
                printf '%s\n' "$changelog_content"
            } > "$changelog_file" || return "$BRIK_EXIT_IO_FAILURE"
        fi

        # Record the changelog audit object: path consumed downstream, entries
        # count for at-a-glance density, generated_at as ISO-8601 for SLO/SLI
        # tracing. Skipped on the idempotent re-run path (early-return above)
        # because no new changelog is produced.
        if command -v jq >/dev/null 2>&1; then
            local _cl_count _cl_ts _cl_obj
            _cl_count="$(changelog.count_entries "$changelog_content" 2>/dev/null || printf '0')"
            # Sanitize: --argjson is fatal on a non-integer value. Defensive
            # against helper edge cases and exotic locales.
            [[ "$_cl_count" =~ ^[0-9]+$ ]] || _cl_count=0
            _cl_ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '')"
            _cl_obj="$(jq -nc \
                --arg path           "$changelog_file" \
                --argjson entries    "$_cl_count" \
                --arg generated_at   "$_cl_ts" \
                '{path: $path, entries_count: $entries}
                 + ( if $generated_at != "" then { generated_at: $generated_at } else {} end )')"
            report.record_object "release" "business" "changelog" "$_cl_obj" 2>/dev/null || true
        fi
    fi

    # Patch package.json version if present.
    local pkg="${BRIK_WORKSPACE:-.}/package.json"
    if [[ -f "$pkg" ]] && command -v jq >/dev/null 2>&1; then
        local tmp
        tmp="$(mktemp)" || return "$BRIK_EXIT_IO_FAILURE"
        jq --arg v "$version" '.version = $v' "$pkg" > "$tmp" || {
            rm -f "$tmp"
            return "$BRIK_EXIT_IO_FAILURE"
        }
        mv "$tmp" "$pkg" || return "$BRIK_EXIT_IO_FAILURE"
    fi

    brik.use transverse.git
    # Apply the git identity resolved by stages.init (BRIK_GIT_USER_EMAIL /
    # BRIK_GIT_USER_NAME) before committing. CI runners are ephemeral and
    # rarely have ~/.gitconfig; without this step `git commit` fails with
    # "Author identity unknown".
    transverse.git.config_identity
    # --fail-if-empty preserves the pre-migration hard-fail semantics: a clean
    # working tree at this point indicates a bug in the release prepare flow
    # (changelog + version patch should have produced a diff), not an
    # idempotent re-run.
    transverse.git.commit_all "release: $version" --fail-if-empty || return "$BRIK_EXIT_EXTERNAL_FAIL"

    log.info "release prepared: $version"
    return 0
}

# Finalize a release: create annotated tag via git.tag.
_stages.release._finalize() {
    local version="$1"
    local tag_prefix="$2"

    local tag_name="${tag_prefix}${version}"
    local -a tag_args=("$tag_name" --message "Release $version")
    local _is_dry_run="false"
    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        tag_args+=(--dry-run)
        _is_dry_run="true"
    fi

    git.tag "${tag_args[@]}" || return $?

    # Record the tag's audit-grade metadata. In dry-run the tag is not
    # actually created so sha is null; otherwise resolve it from the
    # local repo. annotated is always true (we use --message).
    local _tag_sha_json="null"
    if [[ "$_is_dry_run" != "true" ]] && command -v git >/dev/null 2>&1; then
        local _sha
        _sha="$(git -C "${BRIK_WORKSPACE:-.}" rev-parse "refs/tags/${tag_name}^{commit}" 2>/dev/null)" || _sha=""
        [[ -n "$_sha" ]] && _tag_sha_json="\"$_sha\""
    fi
    if command -v jq >/dev/null 2>&1; then
        local _tag_obj
        _tag_obj="$(jq -nc \
            --arg name "$tag_name" \
            --argjson sha "$_tag_sha_json" \
            --argjson dry_run "$_is_dry_run" \
            '{name: $name, sha: $sha, annotated: true, dry_run: $dry_run}')"
        report.record_object "release" "business" "tag" "$_tag_obj" 2>/dev/null || true
    fi

    log.info "release finalized: $tag_name"
    return 0
}
