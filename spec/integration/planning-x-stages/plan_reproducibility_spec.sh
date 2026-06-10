Describe "brik plan reproducibility (L.6)"
  # Chantier promise: on the same commit, with a 10-minute gap,
  # `brik plan --out` produces a strictly identical plan (empty diff).
  # An empty time gap is enough here -- the planner does not embed
  # timestamps -- but we still wait a beat between runs so a regression
  # that pulls in EPOCHREALTIME or `date` shows up immediately.

  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_repo() {
    mock.infra.setup
    REPO="$(mktemp -d)"
    (
      cd "$REPO"
      git init -q -b main
      git config user.email "repro@brik.dev"
      git config user.name "repro"
      cat > brik.yml <<'YAML'
version: 1
project:
  name: repro
pipeline:
  selection:
    mode: balanced
YAML
      cat > package.json <<'JSON'
{"name":"repro","version":"0.1.0"}
JSON
      mkdir -p src
      echo "export const x = 1;" > src/index.ts
      git add -A >/dev/null
      git commit -q -m "baseline"
      git checkout -q -b feature
      echo "export const y = 2;" >> src/index.ts
      git add -A >/dev/null
      git commit -q -m "feature"
    )
  }
  cleanup_repo() {
    mock.infra.teardown
    rm -rf "$REPO"
  }
  Before 'setup_repo'
  After 'cleanup_repo'

  It "two consecutive invocations produce byte-identical plan.json"
    "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan-1.json" >/dev/null
    sleep 1
    "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan-2.json" >/dev/null
    When call cmp -s "$REPO/.brik-logs/plan-1.json" "$REPO/.brik-logs/plan-2.json"
    The status should equal 0
  End

  It "the fingerprint stays stable across runs"
    "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan-1.json" >/dev/null
    sleep 1
    "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan-2.json" >/dev/null
    fp1=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-1.json")
    fp2=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-2.json")
    When call test "$fp1" = "$fp2"
    The status should equal 0
  End

  It "differs when the planning mode changes"
    "$BRIK_BIN" plan --workspace "$REPO" --mode safe \
      --out "$REPO/.brik-logs/plan-safe.json" >/dev/null
    "$BRIK_BIN" plan --workspace "$REPO" --mode balanced \
      --out "$REPO/.brik-logs/plan-balanced.json" >/dev/null
    fp_safe=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-safe.json")
    fp_balanced=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-balanced.json")
    # Modes drive different decisions for the verify grid; the
    # fingerprint must change so adapters can cache per-mode.
    When call test "$fp_safe" != "$fp_balanced"
    The status should equal 0
  End

  It "differs when an opt-in flag flips a stage from skip to run"
    "$BRIK_BIN" plan --workspace "$REPO" \
      --out "$REPO/.brik-logs/plan-nopkg.json" >/dev/null
    "$BRIK_BIN" plan --workspace "$REPO" --with-package \
      --out "$REPO/.brik-logs/plan-withpkg.json" >/dev/null
    fp1=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-nopkg.json")
    fp2=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan-withpkg.json")
    When call test "$fp1" != "$fp2"
    The status should equal 0
  End
End
