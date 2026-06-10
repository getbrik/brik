#!/usr/bin/env bash
# @script bench-plan
# @description Benchmark `brik plan` against a synthetic monorepo fixture
#   so the CI gate (V.4 of the architecture refactor) can catch a
#   planner regression before it lands.
#
# Generates a deterministic fixture of ~5,000 files distributed across
# stack-typical extensions (.ts, .py, .java, .rs, ...) so impact globs
# actually have something to match. Runs `brik plan` $RUNS times and
# emits p50/p99 to stdout plus a JSON report at $OUT.
#
# Gates:
#   --max-p50-ms <ms>   default 800
#   --max-p99-ms <ms>   default 2000
#
# Usage:
#   scripts/bench-plan.sh
#   scripts/bench-plan.sh --runs 20 --out /tmp/bench.json
#   scripts/bench-plan.sh --max-p50-ms 1200 --max-p99-ms 3000

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
BRIK_BIN="${BRIK_BIN:-${ROOT}/bin/brik}"

RUNS=10
FILES=5000
MAX_P50_MS=800
MAX_P99_MS=2000
OUT=""
WORKSPACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs)        RUNS="$2"; shift 2 ;;
        --files)       FILES="$2"; shift 2 ;;
        --max-p50-ms)  MAX_P50_MS="$2"; shift 2 ;;
        --max-p99-ms)  MAX_P99_MS="$2"; shift 2 ;;
        --out)         OUT="$2"; shift 2 ;;
        --workspace)   WORKSPACE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf '[bench-plan] unknown option: %s\n' "$1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { printf '[bench-plan] jq required\n' >&2; exit 69; }
[[ -x "$BRIK_BIN" ]] || { printf '[bench-plan] brik not found at: %s\n' "$BRIK_BIN" >&2; exit 66; }

if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE="$(mktemp -d -t brik-bench-plan.XXXXXX)"
    OWNS_WORKSPACE=1
else
    OWNS_WORKSPACE=0
fi

times_file=""
infra_dir=""
cleanup() {
    [[ "$OWNS_WORKSPACE" -eq 1 ]] && rm -rf "$WORKSPACE"
    [[ -n "$times_file" ]] && rm -f "$times_file"
    [[ -n "$infra_dir" ]] && rm -rf "$infra_dir"
}
trap cleanup EXIT

# brik plan resolves the mandatory infrastructure referential and stamps its
# fingerprint into the plan: the bench provisions a minimal instance (outside
# the workspace so the git fixture stays untouched) and measures that cost as
# part of real plan derivation.
if [[ -z "${BRIK_INFRA_DIR:-}" && -z "${BRIK_INFRA_REPO:-}" ]]; then
    infra_dir="$(mktemp -d -t brik-bench-infra.XXXXXX)"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "${infra_dir}/referential.yml"
    export BRIK_INFRA_DIR="$infra_dir"
fi

printf '[bench-plan] workspace: %s\n' "$WORKSPACE"
printf '[bench-plan] generating fixture (%d files, deterministic)...\n' "$FILES"

cat > "$WORKSPACE/brik.yml" <<'YAML'
version: 1
project:
  name: bench-monorepo
pipeline:
  selection:
    mode: balanced
YAML

cat > "$WORKSPACE/package.json" <<'JSON'
{
  "name": "bench-monorepo",
  "version": "0.1.0",
  "scripts": {}
}
JSON

# Spread N files across 100 dirs * 50 files. Extension mix is intentional
# (typescript dominant + a slice of every other stack so per-stage impact
# globs all have candidates to match).
per_dir=50
n_dirs=$(( (FILES + per_dir - 1) / per_dir ))
exts=(ts ts ts ts js py java rs cs go md)
n_exts=${#exts[@]}
i=0
for d in $(seq 1 "$n_dirs"); do
    sub="$WORKSPACE/src/mod_$d"
    mkdir -p "$sub"
    for f in $(seq 1 "$per_dir"); do
        [[ $i -ge $FILES ]] && break
        ext_idx=$(( i % n_exts ))
        ext="${exts[$ext_idx]}"
        printf '// fixture file %d-%d\n' "$d" "$f" > "$sub/file_${f}.${ext}"
        i=$((i + 1))
    done
done

(
    cd "$WORKSPACE"
    git init -q -b main
    git config user.email "bench@brik.dev"
    git config user.name "bench"
    git add -A >/dev/null 2>&1
    git commit -q -m "fixture: bench-plan baseline"
    git checkout -q -b feature/touch
    printf '// touch\n' >> "src/mod_1/file_1.ts"
    git add -A >/dev/null 2>&1
    git commit -q -m "feature: touch one ts file"
)

printf '[bench-plan] warming up...\n'
"$BRIK_BIN" plan --workspace "$WORKSPACE" --mode balanced \
    --out "$WORKSPACE/.brik-logs/warmup.json" >/dev/null 2>&1 || true

printf '[bench-plan] %d runs...\n' "$RUNS"

times_file="$(mktemp -t brik-bench-times.XXXXXX)"

for run in $(seq 1 "$RUNS"); do
    t0=$EPOCHREALTIME
    "$BRIK_BIN" plan --workspace "$WORKSPACE" --mode balanced \
        --out "$WORKSPACE/.brik-logs/plan-${run}.json" >/dev/null 2>&1
    t1=$EPOCHREALTIME
    ms=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.0f", (b-a)*1000 }')
    printf '%d\n' "$ms" >> "$times_file"
    printf '  run %2d: %s ms\n' "$run" "$ms"
done

sorted="$(sort -n <"$times_file")"
n="$(wc -l <"$times_file" | tr -d ' ')"
pct() {
    local p="$1"
    local idx
    idx=$(( (p * n + 99) / 100 ))
    [[ $idx -lt 1 ]] && idx=1
    [[ $idx -gt $n ]] && idx=$n
    printf '%s' "$sorted" | sed -n "${idx}p"
}
p50="$(pct 50)"
p99="$(pct 99)"
min="$(printf '%s' "$sorted" | head -1)"
max="$(printf '%s' "$sorted" | tail -1)"

printf '\n[bench-plan] runs=%d files=%d  min=%s ms  p50=%s ms  p99=%s ms  max=%s ms\n' \
    "$RUNS" "$FILES" "$min" "$p50" "$p99" "$max"
printf '[bench-plan] gates: p50<=%s ms  p99<=%s ms\n' "$MAX_P50_MS" "$MAX_P99_MS"

if [[ -n "$OUT" ]]; then
    jq -n \
        --argjson runs "$RUNS" \
        --argjson files "$FILES" \
        --argjson p50 "$p50" \
        --argjson p99 "$p99" \
        --argjson min "$min" \
        --argjson max "$max" \
        --argjson max_p50 "$MAX_P50_MS" \
        --argjson max_p99 "$MAX_P99_MS" \
        '{runs:$runs, files:$files, p50_ms:$p50, p99_ms:$p99, min_ms:$min, max_ms:$max,
          gate:{max_p50_ms:$max_p50, max_p99_ms:$max_p99}}' > "$OUT"
    printf '[bench-plan] wrote %s\n' "$OUT"
fi

rc=0
if (( p50 > MAX_P50_MS )); then
    printf '[bench-plan] FAIL: p50=%s ms exceeds gate %s ms\n' "$p50" "$MAX_P50_MS" >&2
    rc=1
fi
if (( p99 > MAX_P99_MS )); then
    printf '[bench-plan] FAIL: p99=%s ms exceeds gate %s ms\n' "$p99" "$MAX_P99_MS" >&2
    rc=1
fi
exit "$rc"
