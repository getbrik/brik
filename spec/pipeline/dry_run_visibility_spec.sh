Describe "pipeline.sh - dry-run visibility"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"

  setup_pipeline() {
    PIPELINE_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$PIPELINE_LOG_DIR"
    export BRIK_WORKSPACE="$PIPELINE_LOG_DIR"
    export BRIK_CONFIG_FILE="$PIPELINE_LOG_DIR/brik.yml"
    : > "$BRIK_CONFIG_FILE"
    export BRIK_RUN_ID="run-dryrun-test"
    # Mock every stages.* so pipeline.run does not exercise real bodies.
    stages.init()            { return 0; }
    stages.release()         { return 0; }
    stages.build()           { return 0; }
    stages.lint()            { return 0; }
    stages.sast()            { return 0; }
    stages.scan()            { return 0; }
    stages.test()            { return 0; }
    stages.package()         { return 0; }
    stages.container_scan()  { return 0; }
    stages.deploy()          { return 0; }
    stages.notify()          { return 0; }
  }
  cleanup_pipeline() {
    rm -rf "$PIPELINE_LOG_DIR"
    unset BRIK_RUN_ID BRIK_DRY_RUN
  }
  Before 'setup_pipeline'
  After 'cleanup_pipeline'

  # ---------------------------------------------------------------------
  # _pipeline._stamp_dry_run direct
  # ---------------------------------------------------------------------
  Describe "_pipeline._stamp_dry_run"
    It "stamps pipeline.tech.dry_run=true when BRIK_DRY_RUN=true"
      stamp_with_flag() {
        printf '{"pipeline":{"id":"123"}}\n' > "$PIPELINE_LOG_DIR/aggregate-report.json"
        BRIK_DRY_RUN=true _pipeline._stamp_dry_run
        jq -r '.pipeline.tech.dry_run' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call stamp_with_flag
      The output should equal "true"
    End

    It "leaves the backend untouched when BRIK_DRY_RUN is unset"
      stamp_without_flag() {
        printf '{"pipeline":{"id":"123"}}\n' > "$PIPELINE_LOG_DIR/aggregate-report.json"
        unset BRIK_DRY_RUN
        _pipeline._stamp_dry_run
        jq -r '.pipeline.tech.dry_run // "absent"' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call stamp_without_flag
      The output should equal "absent"
    End

    It "leaves the backend untouched when BRIK_DRY_RUN=false"
      stamp_with_false() {
        printf '{"pipeline":{"id":"123"}}\n' > "$PIPELINE_LOG_DIR/aggregate-report.json"
        BRIK_DRY_RUN=false _pipeline._stamp_dry_run
        jq -r '.pipeline.tech.dry_run // "absent"' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call stamp_with_false
      The output should equal "absent"
    End

    It "preserves the existing pipeline.context when stamping dry_run"
      stamp_preserves_context() {
        printf '{"pipeline":{"id":"123","context":"release"}}\n' > "$PIPELINE_LOG_DIR/aggregate-report.json"
        BRIK_DRY_RUN=true _pipeline._stamp_dry_run
        jq -r '"\(.pipeline.context):\(.pipeline.tech.dry_run)"' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call stamp_preserves_context
      The output should equal "release:true"
    End
  End

  # ---------------------------------------------------------------------
  # pipeline.run end-to-end
  # ---------------------------------------------------------------------
  Describe "pipeline.run with BRIK_DRY_RUN=true"
    It "emits a DRY-RUN MODE banner on stderr"
      run_with_dry_run() {
        BRIK_DRY_RUN=true pipeline.run >/dev/null
      }
      When call run_with_dry_run
      The stderr should include "DRY-RUN MODE: BRIK_DRY_RUN=true"
      The stderr should include "Destructive actions will be skipped"
    End

    It "stamps pipeline.tech.dry_run=true into the aggregate"
      run_check_aggregate() {
        BRIK_DRY_RUN=true pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.tech.dry_run' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_aggregate
      The output should equal "true"
    End
  End

  Describe "pipeline.run without BRIK_DRY_RUN"
    It "does not emit a DRY-RUN MODE banner"
      run_clean() {
        unset BRIK_DRY_RUN
        pipeline.run >/dev/null
      }
      When call run_clean
      The stderr should not include "DRY-RUN MODE"
    End

    It "leaves pipeline.tech.dry_run absent in the aggregate"
      run_check_no_stamp() {
        unset BRIK_DRY_RUN
        pipeline.run >/dev/null 2>&1
        jq -r '.pipeline.tech.dry_run // "absent"' "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_no_stamp
      The output should equal "absent"
    End
  End

  # ---------------------------------------------------------------------
  # Markdown rendering carries the banner
  # ---------------------------------------------------------------------
  Describe "report.render markdown"
    It "prints a > DRY-RUN blockquote when pipeline.tech.dry_run is true"
      render_md_dryrun() {
        BRIK_DRY_RUN=true pipeline.run >/dev/null 2>&1
        report.render --format md >/dev/null 2>&1
        head -5 "$PIPELINE_LOG_DIR/aggregate-report.md"
      }
      When call render_md_dryrun
      The output should include "DRY-RUN"
      The output should include "BRIK_DRY_RUN=true"
    End

    It "does not print the blockquote on a regular run"
      render_md_clean() {
        unset BRIK_DRY_RUN
        pipeline.run >/dev/null 2>&1
        report.render --format md >/dev/null 2>&1
        head -5 "$PIPELINE_LOG_DIR/aggregate-report.md"
      }
      When call render_md_clean
      The output should not include "DRY-RUN"
    End
  End

  # ---------------------------------------------------------------------
  # Per-stage tech.dry_run marker (deploy/package/notify/release)
  # ---------------------------------------------------------------------
  Describe "per-stage tech.dry_run stamp via stage.run"
    It "records tech.dry_run=true on deploy when BRIK_DRY_RUN=true"
      run_check_deploy() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages[] | select(.stage=="deploy") | .tech.dry_run' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_deploy
      The output should equal "true"
    End

    It "records tech.dry_run=true on package when BRIK_DRY_RUN=true"
      run_check_package() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages[] | select(.stage=="package") | .tech.dry_run' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_package
      The output should equal "true"
    End

    It "records tech.dry_run=true on notify when BRIK_DRY_RUN=true"
      run_check_notify() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages[] | select(.stage=="notify") | .tech.dry_run' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_notify
      The output should equal "true"
    End

    It "leaves tech.dry_run absent on build (not an affected stage)"
      run_check_build() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages[] | select(.stage=="build") | .tech.dry_run // "absent"' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_build
      The output should equal "absent"
    End

    It "leaves tech.dry_run absent on deploy when BRIK_DRY_RUN is unset"
      run_check_deploy_clean() {
        unset BRIK_DRY_RUN
        pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        jq -r '.stages[] | select(.stage=="deploy") | .tech.dry_run // "absent"' \
          "$PIPELINE_LOG_DIR/aggregate-report.json"
      }
      When call run_check_deploy_clean
      The output should equal "absent"
    End
  End

  Describe "Markdown stages table marker"
    It "appends (dry-run) on impacted rows in the stages table"
      render_md_stages() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        report.render --format md >/dev/null 2>&1
        cat "$PIPELINE_LOG_DIR/aggregate-report.md"
      }
      When call render_md_stages
      The output should include "deploy"
      The output should include "_(dry-run)_"
    End
  End

  Describe "Markdown Business (per-stage payload) section"
    It "appends (dry-run) to impacted stage headings in the Business section"
      render_md_business() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        report.render --format md >/dev/null 2>&1
        # Pull the lines that look like "### <stage>" so the assertion is not
        # confused by the (dry-run) marker that the stages table also emits.
        grep -E "^### " "$PIPELINE_LOG_DIR/aggregate-report.md"
      }
      When call render_md_business
      The output should include "### deploy _(dry-run)_"
      The output should include "### release _(dry-run)_"
      The output should include "### package _(dry-run)_"
    End

    It "leaves non-impacted stage headings untouched"
      render_md_business_clean() {
        BRIK_DRY_RUN=true pipeline.run --with-release --with-package --with-deploy >/dev/null 2>&1
        report.render --format md >/dev/null 2>&1
        grep -E "^### (build|lint|sast|scan|test)" "$PIPELINE_LOG_DIR/aggregate-report.md" || true
      }
      When call render_md_business_clean
      The output should not include "_(dry-run)_"
    End
  End
End
