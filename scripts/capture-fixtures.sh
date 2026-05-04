#!/usr/bin/env bash
# capture-fixtures.sh - re-capture SARIF/CycloneDX/raw fixtures from real tool runs.
#
# This script reproduces the fixtures under spec/fixtures/ by running each
# tool inside its corresponding Brik runner image against either the brik
# repo itself or briklab test-projects. Fixtures land back at the same paths
# documented in spec/fixtures/README.md.
#
# Usage: ./scripts/capture-fixtures.sh
# Requirements: docker, jq, briklab repo at ../briklab, brik runner images pulled.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIKLAB_ROOT="${BRIKLAB_ROOT:-$(cd "$REPO_ROOT/../briklab" 2>/dev/null && pwd || true)}"
FIX_DIR="$REPO_ROOT/spec/fixtures"
TMP_DIR="$(mktemp -d /tmp/brik-fixtures.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$FIX_DIR/sarif" "$FIX_DIR/sbom" "$FIX_DIR/raw"

ANALYSIS_IMG="${ANALYSIS_IMG:-ghcr.io/getbrik/brik-runner-analysis:latest}"
SCANNER_IMG="${SCANNER_IMG:-ghcr.io/getbrik/brik-runner-scanner:latest}"
NODE_IMG="${NODE_IMG:-ghcr.io/getbrik/brik-runner-node:22}"
PYTHON_IMG="${PYTHON_IMG:-ghcr.io/getbrik/brik-runner-python:3.13}"

log() { printf '\033[1;34m[capture]\033[0m %s\n' "$*"; }

# Trim a SARIF file to keep only rules referenced by results.
trim_sarif() {
    local in="$1" out="$2"
    jq '
      (.runs[0].results | map(.ruleId) | unique) as $usedIds
      | .runs[0].tool.driver.rules |= map(select(.id as $rid | $usedIds | index($rid)))
      | .
    ' "$in" > "$out"
}

# Semgrep on the brik repo (bash codebase, real findings)
log "semgrep on brik repo"
docker run --rm \
    -v "$REPO_ROOT:/src:ro" \
    -v "$TMP_DIR:/out" \
    --workdir /src \
    "$ANALYSIS_IMG" \
    semgrep scan --config=auto --sarif --output=/out/semgrep-full.sarif --quiet --no-error
trim_sarif "$TMP_DIR/semgrep-full.sarif" "$FIX_DIR/sarif/semgrep.sarif"

# Eslint: synthetic-but-real dirty JS + clean baseline
log "eslint on dirty JS fixture"
mkdir -p "$TMP_DIR/dirty-js/src"
cat > "$TMP_DIR/dirty-js/src/bad.js" <<'JS'
var x = 1
let unused = 2
function bad(  ) {
  if (x == "1") { console.log("loose equality") }
  return undeclared
}
JS
cat > "$TMP_DIR/dirty-js/eslint.config.mjs" <<'MJS'
import js from "@eslint/js";
export default [
  js.configs.recommended,
  { rules: { "no-unused-vars": "warn", "eqeqeq": "error", "no-undef": "error" } }
];
MJS
echo '{"name":"fixture-dirty","version":"0.0.0","type":"module"}' > "$TMP_DIR/dirty-js/package.json"
docker run --rm \
    -v "$TMP_DIR/dirty-js:/src" \
    -v "$TMP_DIR:/out" \
    --workdir /src \
    "$NODE_IMG" \
    sh -c '
      npm install --silent eslint @eslint/js @microsoft/eslint-formatter-sarif >/dev/null 2>&1
      npx eslint src/ --format @microsoft/eslint-formatter-sarif --output-file /out/eslint-dirty.sarif >/dev/null 2>&1 || true
    '
cp "$TMP_DIR/eslint-dirty.sarif" "$FIX_DIR/sarif/eslint.sarif"

if [ -d "$BRIKLAB_ROOT/test-projects/node-complete" ]; then
    log "eslint on briklab node-complete (clean baseline)"
    docker run --rm \
        -v "$BRIKLAB_ROOT/test-projects/node-complete:/src" \
        -v "$TMP_DIR:/out" \
        --workdir /src \
        "$NODE_IMG" \
        sh -c '
          npm ci --silent >/dev/null 2>&1
          npm install --no-save --silent @microsoft/eslint-formatter-sarif >/dev/null 2>&1
          npx eslint . --format @microsoft/eslint-formatter-sarif --output-file /out/eslint-empty.sarif >/dev/null 2>&1 || true
        '
    cp "$TMP_DIR/eslint-empty.sarif" "$FIX_DIR/sarif/eslint-empty.sarif"
fi

# Ruff: dirty Python fixture + clean baseline
log "ruff on dirty Python fixture"
mkdir -p "$TMP_DIR/dirty-py"
cat > "$TMP_DIR/dirty-py/bad.py" <<'PY'
import os, sys
import json

x = 1
y =2
def bad( arg1,arg2 ):
    if x==1:
        unused_local = "x"
        return arg1+arg2
    print("done")

bad(1, 2)
PY
docker run --rm \
    -v "$TMP_DIR/dirty-py:/src" \
    -v "$TMP_DIR:/out" \
    --workdir /src \
    -e RUFF_CACHE_DIR=/tmp/ruff-cache \
    "$PYTHON_IMG" \
    sh -c '
      pip install --quiet ruff >/dev/null 2>&1
      ruff check . --output-format sarif --select E,F,W,I > /out/ruff-dirty.sarif 2>&1 || true
    '
cp "$TMP_DIR/ruff-dirty.sarif" "$FIX_DIR/sarif/ruff.sarif"

if [ -d "$BRIKLAB_ROOT/test-projects/python-complete" ]; then
    log "ruff on briklab python-complete (clean baseline)"
    docker run --rm \
        -v "$BRIKLAB_ROOT/test-projects/python-complete:/src:ro" \
        -v "$TMP_DIR:/out" \
        --workdir /src \
        -e RUFF_CACHE_DIR=/tmp/ruff-cache \
        "$PYTHON_IMG" \
        sh -c '
          pip install --quiet ruff >/dev/null 2>&1
          ruff check . --output-format sarif > /out/ruff-empty.sarif 2>&1 || true
        '
    cp "$TMP_DIR/ruff-empty.sarif" "$FIX_DIR/sarif/ruff-empty.sarif"
fi

# Osv-scanner SARIF + CycloneDX (single project source)
if [ -d "$BRIKLAB_ROOT/test-projects/node-complete" ]; then
    log "osv-scanner on node-complete (no project filter)"
    mkdir -p "$TMP_DIR/node-fresh"
    cp "$BRIKLAB_ROOT/test-projects/node-complete/package.json" "$TMP_DIR/node-fresh/"
    cp "$BRIKLAB_ROOT/test-projects/node-complete/package-lock.json" "$TMP_DIR/node-fresh/"
    docker run --rm \
        -v "$TMP_DIR/node-fresh:/src:ro" \
        -v "$TMP_DIR:/out" \
        --workdir /src \
        "$SCANNER_IMG" \
        sh -c '
          osv-scanner scan source --format sarif --output /out/osv.sarif --recursive /src >/dev/null 2>&1 || true
          osv-scanner scan source --format cyclonedx-1-5 --output /out/osv.cdx.json --recursive /src >/dev/null 2>&1 || true
        '
    cp "$TMP_DIR/osv.sarif" "$FIX_DIR/sarif/osv-scanner.sarif"
    cp "$TMP_DIR/osv.cdx.json" "$FIX_DIR/sbom/osv-scanner.cdx.json"
fi

# Gitleaks: native SARIF + raw JSON (both useful)
log "gitleaks on brik repo (native SARIF + raw JSON)"
docker run --rm \
    -v "$REPO_ROOT:/src:ro" \
    -v "$TMP_DIR:/out" \
    "$SCANNER_IMG" \
    sh -c '
      gitleaks dir /src --report-format sarif --report-path /out/gitleaks.sarif --no-banner --exit-code 0 >/dev/null 2>&1 || true
      gitleaks dir /src --report-format json  --report-path /out/gitleaks.json  --no-banner --exit-code 0 >/dev/null 2>&1 || true
    '
trim_sarif "$TMP_DIR/gitleaks.sarif" "$FIX_DIR/sarif/gitleaks.sarif"
cp "$TMP_DIR/gitleaks.json" "$FIX_DIR/raw/gitleaks.json"

# Checkov: Dockerfile IaC scan
if [ -d "$BRIKLAB_ROOT/test-projects/node-complete" ]; then
    log "checkov on node-complete Dockerfile"
    docker run --rm \
        -v "$BRIKLAB_ROOT/test-projects/node-complete:/src:ro" \
        -v "$TMP_DIR:/out" \
        --workdir /src \
        "$ANALYSIS_IMG" \
        sh -c 'checkov -d /src --framework dockerfile -o sarif --output-file-path /out >/dev/null 2>&1 || true'
    if [ -f "$TMP_DIR/results_sarif.sarif" ]; then
        cp "$TMP_DIR/results_sarif.sarif" "$FIX_DIR/sarif/checkov.sarif"
    fi
fi

# Prettier + tsc raw outputs (converter inputs)
log "prettier raw output (converter input)"
mkdir -p "$TMP_DIR/dirty-fmt/src"
echo "var x = 1;let y=2" > "$TMP_DIR/dirty-fmt/src/bad-prettier.js"
docker run --rm \
    -v "$TMP_DIR/dirty-fmt:/src" \
    -v "$TMP_DIR:/out" \
    --workdir /src \
    "$NODE_IMG" \
    sh -c 'npx --yes --package=prettier@3 -- prettier --check src/bad-prettier.js > /out/prettier.txt 2>&1 || true'
cp "$TMP_DIR/prettier.txt" "$FIX_DIR/raw/prettier.txt"

log "tsc raw output (converter input)"
mkdir -p "$TMP_DIR/dirty-ts/src"
echo "const x: number = \"oops\"; const y = unused;" > "$TMP_DIR/dirty-ts/src/bad.ts"
cat > "$TMP_DIR/dirty-ts/tsconfig.json" <<'TC'
{"compilerOptions":{"strict":true,"noEmit":true,"target":"ES2022","module":"ES2022","moduleResolution":"bundler"}}
TC
docker run --rm \
    -v "$TMP_DIR/dirty-ts:/src" \
    -v "$TMP_DIR:/out" \
    --workdir /src \
    "$NODE_IMG" \
    sh -c 'npx --yes --package=typescript -- tsc --noEmit > /out/tsc.txt 2>&1 || true'
cp "$TMP_DIR/tsc.txt" "$FIX_DIR/raw/tsc.txt"

# Validate every fixture against the bundled schemas
log "validating fixtures against bundled schemas"
if command -v jv >/dev/null 2>&1; then
    fail=0
    for f in "$FIX_DIR"/sarif/*.sarif; do
        if ! jv "$REPO_ROOT/schemas/external/sarif-2.1.0.json" "$f" >/dev/null 2>&1; then
            printf '  FAIL: %s\n' "$(basename "$f")"
            fail=1
        fi
    done
    for f in "$FIX_DIR"/sbom/*.cdx.json; do
        if ! jv "$REPO_ROOT/schemas/external/cyclonedx-1.5.schema.json" "$f" >/dev/null 2>&1; then
            printf '  FAIL: %s\n' "$(basename "$f")"
            fail=1
        fi
    done
    if [ "$fail" = 0 ]; then
        log "all fixtures pass schema validation"
    else
        log "schema validation failures"
        exit 1
    fi
else
    log "jv not found; skipping schema validation"
fi

log "done. fixtures live under $FIX_DIR"
