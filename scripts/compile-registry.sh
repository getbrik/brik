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

# Build the ordered list of manifest dirs.
# Builtins (lib/registry/manifests/) always come first; user extensions
# listed in BRIK_REGISTRY_EXTENSIONS_DIRS (colon-separated) are appended.
# A user manifest whose metadata.id collides with a builtin or with an
# earlier extension is a hard error (the v0.7+ chantier will introduce
# spec.replaces semantics for explicit overrides; v0.6 keeps it simple).
manifest_dirs=("${MANIFESTS_DIR}")
if [[ -n "${BRIK_REGISTRY_EXTENSIONS_DIRS:-}" ]]; then
  _saved_IFS="$IFS"
  IFS=':' read -r -a _ext_list <<< "${BRIK_REGISTRY_EXTENSIONS_DIRS}"
  IFS="$_saved_IFS"
  for ext in "${_ext_list[@]}"; do
    [[ -z "$ext" ]] && continue
    if [[ ! -d "$ext" ]]; then
      printf '[compile-registry] extension dir not found: %s\n' "$ext" >&2
      exit 66
    fi
    manifest_dirs+=("$ext")
  done
fi

# Emit one "id": <body> entry per manifest file under <dir>/<kind>/*.yml,
# in the order of manifest_dirs. Collisions (same metadata.id across
# dirs) are a hard error -- v0.7+ will introduce spec.replaces for
# explicit overrides; v0.6 keeps it simple.
_emit_kind() {
  local kind="$1"; shift
  local -a dirs=("$@")
  local -A seen=()
  local first=1 d id f
  for d in "${dirs[@]}"; do
    compgen -G "${d}/${kind}/*.yml" >/dev/null || continue
    for f in "${d}/${kind}"/*.yml; do
      id=$(yq -e '.metadata.id' "$f")
      if [[ -n "${seen[$id]:-}" ]]; then
        printf '[compile-registry] collision: %s id=%s in %s (already from %s)\n' \
          "$kind" "$id" "$f" "${seen[$id]}" >&2
        return 1
      fi
      seen[$id]="$f"
      [[ $first -eq 0 ]] && printf ',\n'
      printf '    "%s": ' "$id"
      yq -o=json '.' "$f" | jq -c '.'
      first=0
    done
  done
}

# Buffer the raw JSON in a sibling temp file so collision errors from
# _emit_kind surface cleanly. Piping directly into jq would leave it
# parsing partial input on collision and obscure the real diagnostic.
raw="${tmp}.raw"
trap 'rm -f "$tmp" "$raw"' EXIT
{
  printf '{\n  "apiVersion": "brik.dev/registry/v1",\n  "stacks": {\n'
  _emit_kind stacks "${manifest_dirs[@]}" || exit 1
  printf '\n  },\n  "stages": {\n'
  _emit_kind stages "${manifest_dirs[@]}" || exit 1
  printf '\n  }\n}\n'
} > "$raw"
jq -S '.' "$raw" > "$tmp"

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
