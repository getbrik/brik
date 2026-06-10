#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module registry/registry
# @description Public API of the Brik registry. All consumers read stack and
# stage metadata through these accessors instead of hardcoded lists.
# Cf. ADR-001 (manifest format) and the A.5 perf bench (eval-cache pattern).

[[ -n "${_BRIK_REGISTRY_LOADED_API:-}" ]] && return 0
_BRIK_REGISTRY_LOADED_API=1

# shellcheck source=_loader.sh
. "${BASH_SOURCE[0]%/*}/_loader.sh"

_registry._explode() {
  local s="$1"
  [[ -z "$s" ]] && return 0
  printf '%s\n' "${s//:/$'\n'}"
}

registry.use() { _registry._load; }

# --- Stack accessors ---

registry.stack.list() {
  _registry._load || return $?
  local id
  for id in "${_REGISTRY_STACK_IDS[@]}"; do printf '%s\n' "$id"; done
}

registry.stack.exists() {
  _registry._load || return $?
  local id="$1"
  [[ -v _REGISTRY_STACK_DISPLAY_NAME[$id] ]] && return 0
  return "$BRIK_EXIT_INVALID_INPUT"
}

registry.stack.display_name() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_STACK_DISPLAY_NAME[$id]}"
}

registry.stack.markers() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_MARKERS_ANY[$id]}"
}

registry.stack.markers_glob() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_MARKERS_GLOB[$id]:-}"
}

registry.stack.cache_paths() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_CACHE_PATHS[$id]:-}"
}

registry.stack.runner_image() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_STACK_RUNNER_IMAGE[$id]}"
}

registry.stack.runner_default_version() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_STACK_RUNNER_DEFAULT_VERSION[$id]}"
}

registry.stack.runner_versions() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_RUNNER_VERSIONS[$id]}"
}

registry.stack.module() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_STACK_MODULE[$id]}"
}

registry.stack.api_required() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_API_REQUIRED[$id]}"
}

registry.stack.api_optional() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_API_OPTIONAL[$id]:-}"
}

# Print the binaries to probe via brik doctor when this stack is detected.
# Returns empty (rc=0) when spec.doctor.tools is unset on the manifest.
registry.stack.doctor_tools() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_DOCTOR_TOOLS[$id]:-}"
}

# Print the conventional build output directories for the stack, one per
# line, in priority order. Used by lib/stages/build.sh to discover artifacts.
registry.stack.artifact_output_dirs() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_ARTIFACT_OUTPUT_DIRS[$id]:-}"
}

# Print the glob patterns of representative artifact files for the stack,
# in priority order. Used by lib/transverse/artifact.sh._find_main_file.
registry.stack.artifact_patterns() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_ARTIFACT_PATTERNS[$id]:-}"
}

# Print glob patterns of source files for the stack (one per line).
# Used by stages whose spec.impact.use_stack_impact = "source"
# (e.g. lint, format) to inherit the stack's impact set.
registry.stack.impact_source() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_IMPACT_SOURCE[$id]:-}"
}

# Print glob patterns of test files for the stack.
# Used by stages whose spec.impact.use_stack_impact = "test".
registry.stack.impact_test() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_IMPACT_TEST[$id]:-}"
}

# Print glob patterns of build/manifest files for the stack
# (package.json, pom.xml, Cargo.toml, ...).
# Used by stages whose spec.impact.use_stack_impact = "build" (e.g. build).
registry.stack.impact_build() {
  _registry._load || return $?
  local id="$1"; registry.stack.exists "$id" || return $?
  _registry._explode "${_REGISTRY_STACK_IMPACT_BUILD[$id]:-}"
}

registry.stack.detect() {
  _registry._load || return $?
  local workspace="$1"
  local id marker glob
  for id in "${_REGISTRY_STACK_IDS[@]}"; do
    if [[ -n "${_REGISTRY_STACK_MARKERS_ANY[$id]:-}" ]]; then
      while IFS= read -r marker; do
        [[ -z "$marker" ]] && continue
        [[ -f "${workspace}/${marker}" ]] && { printf '%s\n' "$id"; return 0; }
      done < <(_registry._explode "${_REGISTRY_STACK_MARKERS_ANY[$id]}")
    fi
    if [[ -n "${_REGISTRY_STACK_MARKERS_GLOB[$id]:-}" ]]; then
      while IFS= read -r glob; do
        [[ -z "$glob" ]] && continue
        compgen -G "${workspace}/${glob}" >/dev/null 2>&1 && { printf '%s\n' "$id"; return 0; }
      done < <(_registry._explode "${_REGISTRY_STACK_MARKERS_GLOB[$id]}")
    fi
  done
  return "$BRIK_EXIT_FAILURE"
}

registry.stack.detect_from_framework() {
  _registry._load || return $?
  local framework="$1"
  local id pair
  for id in "${_REGISTRY_STACK_IDS[@]}"; do
    while IFS= read -r pair; do
      [[ "$pair" == "${framework}="* ]] && { printf '%s\n' "${pair#*=}"; return 0; }
    done < <(_registry._explode "${_REGISTRY_STACK_FRAMEWORKS[$id]:-}")
  done
  return "$BRIK_EXIT_FAILURE"
}

# --- Stage accessors ---

registry.stage.list() {
  _registry._load || return $?
  local id
  for id in "${_REGISTRY_STAGE_IDS[@]}"; do printf '%s\n' "$id"; done
}

registry.stage.exists() {
  _registry._load || return $?
  local id="$1"
  [[ -v _REGISTRY_STAGE_DISPLAY_NAME[$id] ]] && return 0
  local canonical a
  for canonical in "${_REGISTRY_STAGE_IDS[@]}"; do
    if [[ -n "${_REGISTRY_STAGE_ALIASES[$canonical]:-}" ]]; then
      while IFS= read -r a; do
        [[ "$a" == "$id" ]] && return 0
      done < <(_registry._explode "${_REGISTRY_STAGE_ALIASES[$canonical]}")
    fi
  done
  return "$BRIK_EXIT_INVALID_INPUT"
}

registry.stage.resolve_alias() {
  _registry._load || return $?
  local name="$1"
  [[ -v _REGISTRY_STAGE_DISPLAY_NAME[$name] ]] && { printf '%s\n' "$name"; return 0; }
  local canonical a
  for canonical in "${_REGISTRY_STAGE_IDS[@]}"; do
    if [[ -n "${_REGISTRY_STAGE_ALIASES[$canonical]:-}" ]]; then
      while IFS= read -r a; do
        [[ "$a" == "$name" ]] && { printf '%s\n' "$canonical"; return 0; }
      done < <(_registry._explode "${_REGISTRY_STAGE_ALIASES[$canonical]}")
    fi
  done
  printf '%s\n' "$name"
  return "$BRIK_EXIT_INVALID_INPUT"
}

# Helper: load registry, resolve alias to canonical id (in same shell scope
# so subsequent assoc array reads work), then echo $id for the caller via
# `local id; id="$(_registry._resolve_stage_id "$1")"` pattern. Avoids the
# subshell isolation bug: the load and the assoc array reads must happen in
# the SAME shell context.
_registry._resolve_stage_id_or_die() {
  local name="$1"
  if [[ -v _REGISTRY_STAGE_DISPLAY_NAME[$name] ]]; then
    printf '%s' "$name"
    return 0
  fi
  local canonical a
  for canonical in "${_REGISTRY_STAGE_IDS[@]}"; do
    if [[ -n "${_REGISTRY_STAGE_ALIASES[$canonical]:-}" ]]; then
      while IFS= read -r a; do
        [[ "$a" == "$name" ]] && { printf '%s' "$canonical"; return 0; }
      done < <(_registry._explode "${_REGISTRY_STAGE_ALIASES[$canonical]}")
    fi
  done
  return "$BRIK_EXIT_INVALID_INPUT"
}

registry.stage.display_name() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_DISPLAY_NAME[$id]}"
}

registry.stage.function() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_FUNCTION[$id]}"
}

registry.stage.module() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_MODULE[$id]}"
}

registry.stage.placement_slot() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_PLACEMENT_SLOT[$id]}"
}

registry.stage.placement_group() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_PLACEMENT_GROUP[$id]:-}"
}

registry.stage.after() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_PLACEMENT_AFTER[$id]:-}"
}

registry.stage.before() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_PLACEMENT_BEFORE[$id]:-}"
}

registry.stage.runner_class() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_RUNNER_CLASS[$id]}"
}

registry.stage.gate_mode() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_GATE_MODE[$id]}"
}

registry.stage.gate_opt_in_flag() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_GATE_OPT_IN_FLAG[$id]:-}"
}

registry.stage.gate_contexts() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_GATE_CONTEXTS[$id]}"
}

registry.stage.is_destructive() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  [[ "${_REGISTRY_STAGE_DRY_RUN_DESTRUCTIVE[$id]:-false}" == "true" ]]
}

registry.stage.aliases() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_ALIASES[$id]:-}"
}

registry.stage.api_required() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_API_REQUIRED[$id]}"
}

# Print glob patterns from spec.impact.changes for the stage (one per
# line). Empty when the stage opts into use_stack_impact instead.
# Used by the planner to decide whether a stage is impacted by the
# changed-files set.
registry.stage.impact_changes() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  _registry._explode "${_REGISTRY_STAGE_IMPACT_CHANGES[$id]:-}"
}

# Print "source"|"test"|"build" when the stage inherits its impact set
# from the stack (spec.impact.use_stack_impact), or "" when the stage
# declares its own changes patterns.
registry.stage.impact_use_stack_impact() {
  _registry._load || return $?
  local id; id="$(_registry._resolve_stage_id_or_die "$1")" || return $?
  printf '%s\n' "${_REGISTRY_STAGE_IMPACT_USE_STACK_IMPACT[$id]:-}"
}

# --- Provider accessors ---
#
# A provider is one interchangeable implementation of a capability behind a
# testable contract (third manifest family). The binding axis says which
# source selects it: the project (brik.yml), the environment (infrastructure
# referential) or the detected execution context (orchestrator).

registry.provider.list() {
  _registry._load || return $?
  local id
  for id in "${_REGISTRY_PROVIDER_IDS[@]}"; do printf '%s\n' "$id"; done
}

registry.provider.exists() {
  _registry._load || return $?
  local id="$1"
  [[ -v _REGISTRY_PROVIDER_CAPABILITY[$id] ]] && return 0
  return "$BRIK_EXIT_INVALID_INPUT"
}

registry.provider.display_name() {
  _registry._load || return $?
  local id="$1"; registry.provider.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_PROVIDER_DISPLAY_NAME[$id]}"
}

registry.provider.capability() {
  _registry._load || return $?
  local id="$1"; registry.provider.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_PROVIDER_CAPABILITY[$id]}"
}

registry.provider.binding() {
  _registry._load || return $?
  local id="$1"; registry.provider.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_PROVIDER_BINDING[$id]}"
}

registry.provider.contract() {
  _registry._load || return $?
  local id="$1"; registry.provider.exists "$id" || return $?
  printf '%s\n' "${_REGISTRY_PROVIDER_CONTRACT[$id]}"
}

# Print the tools the provider requires, one "name[>=min_version]" per line.
# This list is the source the runner-image tool matrix derives from.
registry.provider.tools() {
  _registry._load || return $?
  local id="$1"; registry.provider.exists "$id" || return $?
  _registry._explode "${_REGISTRY_PROVIDER_TOOLS[$id]:-}"
}

# Print the ids of every provider implementing <capability>.
registry.provider.for_capability() {
  _registry._load || return $?
  local capability="$1" id
  for id in "${_REGISTRY_PROVIDER_IDS[@]}"; do
    [[ "${_REGISTRY_PROVIDER_CAPABILITY[$id]}" == "$capability" ]] && printf '%s\n' "$id"
  done
  return 0
}

# --- Runner class accessors ---
#
# Read lib/registry/runner_classes.yml to resolve the OCI image attached to
# each runner.class declared on a stage manifest (spec.runner.class). Single
# source of truth consumed identically by the GitLab adapter (via dotenv
# exported by init: BRIK_IMG_<CLASS>) and the Jenkins adapter (via
# brikDriver.resolveImage). Avoids the previous duplication where image
# paths were hardcoded in both brik-integrate.yml and brikIntegrate.groovy.
#
# The 'stack' class is dynamic: its image is computed by init from the
# project's stack (node/python/...) and exposed via the env var declared
# under classes.stack.image_env (BRIK_CI_IMAGE).

# Default runner-class registry (bundled). BRIK_RUNNER_CLASSES_FILE overrides
# it at call time, letting e2e / mirror / air-gapped setups point at an
# alternate file (e.g. a stub image fleet) without editing the default. The
# stage that reads this file still runs on its own default bootstrap image.
_BRIK_RUNNER_CLASSES_DEFAULT="${BASH_SOURCE[0]%/*}/runner_classes.yml"

# Resolve a runner_class id to its full OCI image reference.
#
# For a static class, prints "<image>:<tag>" using the values declared in
# runner_classes.yml.
# For a dynamic class (declares image_env instead of image), prints the
# current value of the environment variable named by image_env; fails when
# that variable is unset or empty.
#
# Returns:
#   0 on successful resolution
#   BRIK_EXIT_INVALID_INPUT  unknown class, missing argument, or required
#                            env var unset for a dynamic class
#   BRIK_EXIT_IO_FAILURE     runner_classes.yml not found
#   BRIK_EXIT_MISSING_DEP    yq not on PATH
#
# Usage: registry.runner_class.image <class>
registry.runner_class.image() {
  local class="${1:-}"
  if [[ -z "$class" ]]; then
    printf '[registry] runner_class.image: class id required\n' >&2
    return "$BRIK_EXIT_INVALID_INPUT"
  fi
  local _BRIK_RUNNER_CLASSES_YML="${BRIK_RUNNER_CLASSES_FILE:-$_BRIK_RUNNER_CLASSES_DEFAULT}"
  if [[ ! -f "$_BRIK_RUNNER_CLASSES_YML" ]]; then
    printf '[registry] runner_classes.yml not found: %s\n' \
      "$_BRIK_RUNNER_CLASSES_YML" >&2
    return "$BRIK_EXIT_IO_FAILURE"
  fi
  command -v yq >/dev/null 2>&1 || {
    printf '[registry] yq required for runner_class.image\n' >&2
    return "$BRIK_EXIT_MISSING_DEP"
  }

  # Dynamic case: classes.<class>.image_env declares an env var name.
  local image_env
  image_env="$(yq -r ".classes.\"$class\".image_env // \"\"" \
                "$_BRIK_RUNNER_CLASSES_YML" 2>/dev/null)"
  if [[ -n "$image_env" ]]; then
    local resolved="${!image_env:-}"
    if [[ -z "$resolved" ]]; then
      printf '[registry] runner_class.image: class %s requires %s (unset)\n' \
        "$class" "$image_env" >&2
      return "$BRIK_EXIT_INVALID_INPUT"
    fi
    printf '%s\n' "$resolved"
    return 0
  fi

  # Static case: <image>:<tag>.
  local image tag
  image="$(yq -r ".classes.\"$class\".image // \"\"" \
            "$_BRIK_RUNNER_CLASSES_YML" 2>/dev/null)"
  if [[ -z "$image" ]]; then
    printf '[registry] runner_class.image: unknown class: %s\n' "$class" >&2
    return "$BRIK_EXIT_INVALID_INPUT"
  fi
  tag="$(yq -r ".classes.\"$class\".tag // \"latest\"" \
          "$_BRIK_RUNNER_CLASSES_YML" 2>/dev/null)"
  printf '%s:%s\n' "$image" "$tag"
}


registry.explain() {
  _registry._load || return $?
  printf 'apiVersion: brik.dev/registry/v1\n'
  printf 'cache: %s\n' "$_REGISTRY_CACHE_PATH"
  printf '\nStacks (%d):\n' "${#_REGISTRY_STACK_IDS[@]}"
  local id
  for id in "${_REGISTRY_STACK_IDS[@]}"; do
    printf '  - %-8s : %s (runner: %s:%s)\n' \
      "$id" "${_REGISTRY_STACK_DISPLAY_NAME[$id]}" \
      "${_REGISTRY_STACK_RUNNER_IMAGE[$id]}" \
      "${_REGISTRY_STACK_RUNNER_DEFAULT_VERSION[$id]}"
  done
  printf '\nStages (%d, canonical order):\n' "${#_REGISTRY_STAGE_IDS[@]}"
  for id in "${_REGISTRY_STAGE_IDS[@]}"; do
    printf '  - %-15s -> %-25s (runner: %s, gate: %s)\n' \
      "$id" "${_REGISTRY_STAGE_FUNCTION[$id]}" \
      "${_REGISTRY_STAGE_RUNNER_CLASS[$id]}" \
      "${_REGISTRY_STAGE_GATE_MODE[$id]}"
  done
}
