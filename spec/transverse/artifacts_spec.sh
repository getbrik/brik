Describe "transverse/artifacts.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/artifacts.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_workspace() {
    mock.workspace.setup
    ART_WS="$BRIK_WORKSPACE"
  }
  Before 'setup_workspace'
  After 'mock.workspace.teardown'

  Describe "brik.artifacts.root"
    It "returns BRIK_WORKSPACE/brik-artifacts"
      run_root() {
        brik.artifacts.root
      }
      When call run_root
      The output should equal "$ART_WS/brik-artifacts"
    End

    It "falls back to ./brik-artifacts when BRIK_WORKSPACE is unset"
      run_root_unset() {
        unset BRIK_WORKSPACE
        brik.artifacts.root
      }
      When call run_root_unset
      The output should equal "./brik-artifacts"
    End

    It "does not create the directory (root is a pure query)"
      run_root_no_mkdir() {
        brik.artifacts.root >/dev/null
        [[ -d "$ART_WS/brik-artifacts" ]] && echo "exists" || echo "absent"
      }
      When call run_root_no_mkdir
      The output should equal "absent"
    End
  End

  Describe "brik.artifacts.dir"
    It "returns BRIK_WORKSPACE/brik-artifacts/<stage>"
      run_dir_scan() {
        brik.artifacts.dir scan
      }
      When call run_dir_scan
      The output should equal "$ART_WS/brik-artifacts/scan"
    End

    It "creates the stage directory on first call"
      run_dir_creates() {
        brik.artifacts.dir sast >/dev/null
        [[ -d "$ART_WS/brik-artifacts/sast" ]] && echo "created" || echo "missing"
      }
      When call run_dir_creates
      The output should equal "created"
    End

    It "is idempotent on a second call"
      run_dir_idempotent() {
        brik.artifacts.dir lint >/dev/null
        brik.artifacts.dir lint >/dev/null
        [[ -d "$ART_WS/brik-artifacts/lint" ]] && echo "ok" || echo "missing"
      }
      When call run_dir_idempotent
      The output should equal "ok"
    End

    It "supports hyphenated stage names like container-scan"
      run_dir_hyphenated() {
        brik.artifacts.dir container-scan
      }
      When call run_dir_hyphenated
      The output should equal "$ART_WS/brik-artifacts/container-scan"
    End

    It "creates the hyphenated stage directory on disk"
      run_dir_hyphenated_creates() {
        brik.artifacts.dir container-scan >/dev/null
        [[ -d "$ART_WS/brik-artifacts/container-scan" ]] && echo "created" || echo "missing"
      }
      When call run_dir_hyphenated_creates
      The output should equal "created"
    End

    It "returns non-zero when called without arguments"
      When call brik.artifacts.dir
      The status should not equal 0
      The stderr should not be blank
    End
  End

  Describe "brik.artifacts.path"
    It "returns BRIK_WORKSPACE/brik-artifacts/<stage>/<file>"
      run_path_simple() {
        brik.artifacts.path scan deps.sarif
      }
      When call run_path_simple
      The output should equal "$ART_WS/brik-artifacts/scan/deps.sarif"
    End

    It "creates the parent stage directory"
      run_path_creates_parent() {
        brik.artifacts.path sast sast.sarif >/dev/null
        [[ -d "$ART_WS/brik-artifacts/sast" ]] && echo "ok" || echo "missing"
      }
      When call run_path_creates_parent
      The output should equal "ok"
    End

    It "does not create the file itself (only the directory)"
      run_path_no_file() {
        brik.artifacts.path scan secret.sarif >/dev/null
        [[ -f "$ART_WS/brik-artifacts/scan/secret.sarif" ]] && echo "file" || echo "no-file"
      }
      When call run_path_no_file
      The output should equal "no-file"
    End

    It "supports nested sub-paths and creates intermediate directories"
      run_path_nested() {
        brik.artifacts.path test coverage/cobertura.xml >/dev/null
        [[ -d "$ART_WS/brik-artifacts/test/coverage" ]] && echo "ok" || echo "missing"
      }
      When call run_path_nested
      The output should equal "ok"
    End

    It "returns the full nested path on stdout"
      run_path_nested_string() {
        brik.artifacts.path test coverage/cobertura.xml
      }
      When call run_path_nested_string
      The output should equal "$ART_WS/brik-artifacts/test/coverage/cobertura.xml"
    End

    It "returns non-zero when called with no arguments"
      When call brik.artifacts.path
      The status should not equal 0
      The stderr should not be blank
    End

    It "returns non-zero when called with only a stage"
      When call brik.artifacts.path scan
      The status should not equal 0
      The stderr should not be blank
    End
  End

  # ---------------------------------------------------------------------------
  # brik.logs.* - operational data tree (chantier pipeline-layout-unification)
  #
  # Mirror of brik.artifacts.* for the .brik-logs/ root: forensic data, env
  # file, per-stage logs, lock files. Same depth rule (max 2 levels), same
  # API shape (root/dir/path with side-effecting variants).
  # ---------------------------------------------------------------------------
  Describe "brik.logs.root"
    It "returns BRIK_WORKSPACE/.brik-logs"
      When call brik.logs.root
      The output should equal "$ART_WS/.brik-logs"
    End

    It "falls back to ./.brik-logs when BRIK_WORKSPACE is unset"
      run_logs_root_unset() {
        unset BRIK_WORKSPACE
        brik.logs.root
      }
      When call run_logs_root_unset
      The output should equal "./.brik-logs"
    End

    It "does not create the directory (root is a pure query)"
      run_logs_root_no_mkdir() {
        brik.logs.root >/dev/null
        [[ -d "$ART_WS/.brik-logs" ]] && echo "exists" || echo "absent"
      }
      When call run_logs_root_no_mkdir
      The output should equal "absent"
    End
  End

  Describe "brik.logs.dir"
    It "returns BRIK_WORKSPACE/.brik-logs/<stage>"
      When call brik.logs.dir test
      The output should equal "$ART_WS/.brik-logs/test"
    End

    It "creates the stage directory on first call"
      run_logs_dir_creates() {
        brik.logs.dir release >/dev/null
        [[ -d "$ART_WS/.brik-logs/release" ]] && echo "ok" || echo "missing"
      }
      When call run_logs_dir_creates
      The output should equal "ok"
    End

    It "returns non-zero when called with no argument"
      When call brik.logs.dir
      The status should not equal 0
      The stderr should not be blank
    End
  End

  Describe "brik.logs.path"
    It "returns BRIK_WORKSPACE/.brik-logs/<relpath> and creates parent dirs"
      run_logs_path() {
        brik.logs.path policy.cache.json
      }
      When call run_logs_path
      The output should equal "$ART_WS/.brik-logs/policy.cache.json"
    End

    It "supports a nested relpath and creates intermediate directories"
      run_logs_path_nested() {
        brik.logs.path init/init.log >/dev/null
        [[ -d "$ART_WS/.brik-logs/init" ]] && echo "ok" || echo "missing"
      }
      When call run_logs_path_nested
      The output should equal "ok"
    End

    It "does not create the file itself"
      run_logs_path_no_file() {
        brik.logs.path pipeline.env >/dev/null
        [[ -f "$ART_WS/.brik-logs/pipeline.env" ]] && echo "file" || echo "no-file"
      }
      When call run_logs_path_no_file
      The output should equal "no-file"
    End

    It "returns non-zero when called with no argument"
      When call brik.logs.path
      The status should not equal 0
      The stderr should not be blank
    End
  End
End
