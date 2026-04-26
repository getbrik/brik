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

    log.info "release stage - computing version"

    brik.use version
    brik.use git

    local strategy="${BRIK_RELEASE_STRATEGY:-semver}"
    local tag_prefix="${BRIK_RELEASE_TAG_PREFIX:-v}"

    log.info "release strategy: $strategy, tag prefix: $tag_prefix"

    local current_version
    current_version="$(version.current --from-git-tag --prefix "$tag_prefix")" || {
        log.info "no git tag found, using 0.0.0"
        current_version="0.0.0"
    }

    log.info "current version: $current_version"
    export BRIK_APP_VERSION="$current_version"
    report.record "release" "business" "app_version" "$current_version" 2>/dev/null || true
    pipeline.env.set "BRIK_APP_VERSION" "$current_version"

    # If on a tag (release trigger), prepare and finalize. A failure in either
    # step must propagate so the pipeline (and pipeline-report.json) reflect
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
    [[ "${BRIK_DRY_RUN:-}" == "true" ]] && tag_args+=(--dry-run)

    git.tag "${tag_args[@]}" || return $?

    log.info "release finalized: $tag_name"
    return 0
}
