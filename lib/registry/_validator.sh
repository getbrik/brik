#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module registry/_validator
# @description Validate stack/stage manifests against JSON Schema (jv).
# Sourced by scripts/compile-registry.sh, which gates compilation on
# registry.validate_all_manifests so a malformed manifest never reaches the
# compiled cache. Per ADR-002: first layer of the contract test harness.

[[ -n "${_BRIK_REGISTRY_VALIDATOR_LOADED:-}" ]] && return 0
_BRIK_REGISTRY_VALIDATOR_LOADED=1

# Resolve directories at source time, with a fallback walk for the schema dir
# (validator may be sourced from outside the brik tree).
_BRIK_REGISTRY_VALIDATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BRIK_REGISTRY_SCHEMA_DIR=""
{
  _candidate="$(cd "${_BRIK_REGISTRY_VALIDATOR_DIR}/../../schemas/registry/v1" 2>/dev/null && pwd)"
  if [[ -n "$_candidate" && -d "$_candidate" ]]; then
    _BRIK_REGISTRY_SCHEMA_DIR="$_candidate"
  fi
  unset _candidate
}

_validator._fail() {
  printf '[registry:validator] %s\n' "$*" >&2
  return "$BRIK_EXIT_INVALID_INPUT"
}

_validator._kind() {
  local file="$1"
  local kind
  kind="$(yq -e '.kind' "$file" 2>/dev/null)" || {
    _validator._fail "cannot read .kind from $file"
    return $?
  }
  case "$kind" in
    Stack|Stage|Provider) printf '%s' "$kind" ;;
    *) _validator._fail "unknown kind in $file: $kind (expected Stack, Stage or Provider)"; return $? ;;
  esac
}

_validator._schema() {
  local kind="$1"
  [[ -n "$_BRIK_REGISTRY_SCHEMA_DIR" ]] || { _validator._fail "schema dir not resolved"; return $?; }
  case "$kind" in
    Stack)    printf '%s/stack.schema.json' "$_BRIK_REGISTRY_SCHEMA_DIR" ;;
    Stage)    printf '%s/stage.schema.json' "$_BRIK_REGISTRY_SCHEMA_DIR" ;;
    Provider) printf '%s/provider.schema.json' "$_BRIK_REGISTRY_SCHEMA_DIR" ;;
    *) _validator._fail "no schema for kind=$kind"; return $? ;;
  esac
}

# Validate a single manifest file against its schema via jv.
# Usage: registry.validate_manifest <path>
registry.validate_manifest() {
  local file="$1"
  [[ -f "$file" ]] || { _validator._fail "manifest not found: $file"; return $?; }
  command -v yq >/dev/null 2>&1 || { _validator._fail "yq required"; return $?; }
  command -v jq >/dev/null 2>&1 || { _validator._fail "jq required"; return $?; }
  command -v jv >/dev/null 2>&1 || { _validator._fail "jv required (jsonschema validator)"; return $?; }

  local kind schema
  kind="$(_validator._kind "$file")" || return $?
  schema="$(_validator._schema "$kind")" || return $?
  [[ -f "$schema" ]] || { _validator._fail "schema not found: $schema"; return $?; }

  # jv requires instance file path (stdin is not validated). Write to a
  # tempfile we name ourselves inside a mktemp -d directory. We cannot use
  # `mktemp -t <prefix>-XXXXXX.json` because busybox mktemp (Alpine runner
  # images) rejects a template with anything after the XXXXXX run; naming the
  # file under a temp dir is portable across GNU, BSD and busybox and keeps
  # the .json extension jv uses to pick the JSON parser.
  local _tmpd instance diagnostic rc
  _tmpd="$(mktemp -d)" || {
    _validator._fail "mktemp failed"
    return $?
  }
  instance="$_tmpd/instance.json"
  if ! yq -o=json '.' "$file" > "$instance" 2>/dev/null; then
    _validator._fail "yq parse error on $file"
    rm -rf "$_tmpd"
    return "$BRIK_EXIT_INVALID_INPUT"
  fi
  diagnostic="$(jv "$schema" "$instance" 2>&1)"
  rc=$?
  rm -rf "$_tmpd"
  if [[ $rc -ne 0 ]]; then
    _validator._fail "manifest invalid: $file"
    printf '%s\n' "$diagnostic" >&2
    return "$BRIK_EXIT_INVALID_INPUT"
  fi
  return 0
}

# Validate ALL manifests under lib/registry/manifests/.
registry.validate_all_manifests() {
  local manifest_root="${1:-${_BRIK_REGISTRY_VALIDATOR_DIR}/manifests}"
  local failures=0 total=0 file
  for file in "$manifest_root"/stacks/*.yml "$manifest_root"/stages/*.yml; do
    [[ -f "$file" ]] || continue
    total=$((total + 1))
    if registry.validate_manifest "$file" 2>/dev/null; then
      printf '  OK   %s\n' "${file#"${manifest_root}/"}"
    else
      printf '  FAIL %s\n' "${file#"${manifest_root}/"}" >&2
      registry.validate_manifest "$file" >&2 2>&1 || true
      failures=$((failures + 1))
    fi
  done
  printf 'validated: %s/%s\n' "$((total - failures))" "$total"
  [[ $failures -eq 0 ]]
}
