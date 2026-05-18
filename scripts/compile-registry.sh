#!/usr/bin/env bash
# @script compile-registry
# @description Compile YAML manifests under lib/registry/manifests/ into a single
# canonical JSON cache at lib/registry/cache/registry.json.
#
# Per ADR-001 (manifest format): YAML source is authored, JSON compiled cache is
# read at runtime via jq. This script is invoked by the runner image build
# pipeline and by 'brik extension test' for authors. End users never run yq.
#
# Output: lib/registry/cache/registry.json, jq -S sorted (sha256 stable).
#
# Usage:
#   scripts/compile-registry.sh                       # compile from default location
#   scripts/compile-registry.sh --check               # exit non-zero if cache stale
#   scripts/compile-registry.sh --check-schema-enum   # verify brik.schema.json enum matches language stacks
#   scripts/compile-registry.sh --output PATH         # custom output path

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
MANIFESTS_DIR="${ROOT}/lib/registry/manifests"
CACHE_DIR="${ROOT}/lib/registry/cache"
DEFAULT_OUTPUT="${CACHE_DIR}/registry.json"
PROJECT_SCHEMA="${ROOT}/schemas/config/v1/brik.schema.json"

# Stacks whose role in brik.yml is "project.stack" (language stacks the user
# can declare). Docker is in the registry as a builder helper but is NOT a
# valid project.stack value. Aligned with D.2.4 of the architecture refactor.
LANGUAGE_STACKS=(node java python dotnet rust)

mode="compile"
output="${DEFAULT_OUTPUT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)              mode="check"; shift ;;
    --check-schema-enum)  mode="check-schema-enum"; shift ;;
    --output)             output="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf '[compile-registry] unknown option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done

# --check-schema-enum: verify project.stack enum in brik.schema.json matches
# the LANGUAGE_STACKS set above. CI runs this to catch drift between the
# manifests and the user-facing schema.
if [[ "$mode" == "check-schema-enum" ]]; then
  command -v jq >/dev/null 2>&1 || { printf '[compile-registry] jq required\n' >&2; exit 69; }
  [[ -f "$PROJECT_SCHEMA" ]] || { printf '[compile-registry] schema not found: %s\n' "$PROJECT_SCHEMA" >&2; exit 66; }

  missing=()
  for s in "${LANGUAGE_STACKS[@]}"; do
    [[ -f "${MANIFESTS_DIR}/stacks/${s}.yml" ]] || missing+=("$s")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '[compile-registry] FAIL: language stacks missing manifests: %s\n' "${missing[*]}" >&2
    exit 1
  fi

  expected=$(printf '%s\n' "${LANGUAGE_STACKS[@]}" | jq -R . | jq -s 'sort')
  actual=$(jq '.properties.project.properties.stack.enum | sort' "$PROJECT_SCHEMA")
  if [[ "$expected" != "$actual" ]]; then
    printf '[compile-registry] FAIL: project.stack enum in %s diverges from LANGUAGE_STACKS\n' "$PROJECT_SCHEMA" >&2
    printf '[compile-registry] expected: %s\n' "$(printf '%s\n' "${LANGUAGE_STACKS[@]}" | sort | tr '\n' ',' | sed 's/,$//')" >&2
    printf '[compile-registry] actual:   %s\n' "$(jq -r '.properties.project.properties.stack.enum | sort | join(",")' "$PROJECT_SCHEMA")" >&2
    exit 1
  fi
  printf '[compile-registry] schema enum in sync with %d language stacks\n' "${#LANGUAGE_STACKS[@]}"
  exit 0
fi

command -v yq >/dev/null 2>&1 || { printf '[compile-registry] yq required\n' >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { printf '[compile-registry] jq required\n' >&2; exit 69; }

mkdir -p "$(dirname "$output")"

tmp="$(mktemp "${output}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# Build the registry.json document by streaming each manifest through yq
# (YAML -> JSON) then jq -c (compact one-line per stack/stage), wrapped in the
# enclosing object literal. jq -S at the end gives stable key ordering.
{
  printf '{\n  "apiVersion": "brik.dev/registry/v1",\n  "stacks": {\n'
  first=1
  if compgen -G "${MANIFESTS_DIR}/stacks/*.yml" >/dev/null; then
    for f in "${MANIFESTS_DIR}"/stacks/*.yml; do
      id=$(yq -e '.metadata.id' "$f")
      [[ $first -eq 0 ]] && printf ',\n'
      printf '    "%s": ' "$id"
      yq -o=json '.' "$f" | jq -c '.'
      first=0
    done
  fi
  printf '\n  },\n  "stages": {\n'
  first=1
  if compgen -G "${MANIFESTS_DIR}/stages/*.yml" >/dev/null; then
    for f in "${MANIFESTS_DIR}"/stages/*.yml; do
      id=$(yq -e '.metadata.id' "$f")
      [[ $first -eq 0 ]] && printf ',\n'
      printf '    "%s": ' "$id"
      yq -o=json '.' "$f" | jq -c '.'
      first=0
    done
  fi
  printf '\n  }\n}\n'
} | jq -S '.' > "$tmp"

case "$mode" in
  check)
    if [[ -f "$output" ]] && cmp -s "$tmp" "$output"; then
      printf '[compile-registry] cache up-to-date: %s\n' "$output"
      exit 0
    fi
    printf '[compile-registry] cache STALE: %s\n' "$output" >&2
    printf '[compile-registry] run scripts/compile-registry.sh to regenerate\n' >&2
    exit 1
    ;;
  compile)
    mv "$tmp" "$output"
    trap - EXIT
    size=$(wc -c < "$output")
    sha=$(shasum -a 256 "$output" | awk '{print $1}')
    n_stacks=$(jq -r '.stacks | length' "$output")
    n_stages=$(jq -r '.stages | length' "$output")
    printf '[compile-registry] compiled %s\n' "$output"
    printf '[compile-registry]   stacks: %s\n' "$n_stacks"
    printf '[compile-registry]   stages: %s\n' "$n_stages"
    printf '[compile-registry]   bytes:  %s\n' "$size"
    printf '[compile-registry]   sha256: %s\n' "$sha"
    ;;
esac
