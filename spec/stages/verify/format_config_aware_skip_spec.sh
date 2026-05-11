Describe "verify.format.run - config-aware skip"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/format.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # Same contract as verify.lint: stack defaults must not coerce projects
  # into running a formatter they never opted into via a config file.

  Describe "Tier 2: prettier without project config skips"
    setup_prettier_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '{"name":"x"}\n' > "${TEST_WS}/package.json"
      mock.create_exit "npx" 0
      mock.activate
      export BRIK_QUALITY_FORMAT_TOOL="prettier"
    }
    cleanup_prettier_no_cfg() {
      unset BRIK_QUALITY_FORMAT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_prettier_no_cfg'
    After 'cleanup_prettier_no_cfg'

    It "skips when no .prettierrc and no \"prettier\" key in package.json"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no prettier config found"
    End
  End

  Describe "Tier 2: ruff-format without project config skips"
    setup_rufffmt_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[project]\nname = "x"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_exit "ruff" 0
      mock.activate
      export BRIK_QUALITY_FORMAT_TOOL="ruff-format"
    }
    cleanup_rufffmt_no_cfg() {
      unset BRIK_QUALITY_FORMAT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_rufffmt_no_cfg'
    After 'cleanup_rufffmt_no_cfg'

    It "skips when pyproject.toml lacks [tool.ruff]"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no ruff config found"
    End
  End

  Describe "Tier 2: dotnet-format without .editorconfig skips"
    setup_dotfmt_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_exit "dotnet" 0
      mock.activate
      export BRIK_QUALITY_FORMAT_TOOL="dotnet-format"
    }
    cleanup_dotfmt_no_cfg() {
      unset BRIK_QUALITY_FORMAT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_dotfmt_no_cfg'
    After 'cleanup_dotfmt_no_cfg'

    It "skips when no .editorconfig present"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no dotnet-format config found"
    End
  End

  Describe "Tier 3: prettier auto-detect without project config skips"
    setup_t3_prettier_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '{"name":"x"}\n' > "${TEST_WS}/package.json"
      mock.create_exit "npx" 0
      mock.activate
    }
    cleanup_t3_prettier_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_t3_prettier_no_cfg'
    After 'cleanup_t3_prettier_no_cfg'

    It "skips Node.js auto-detect when no prettier config in package.json"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no prettier config found"
    End
  End

  Describe "Tier 3: ruff auto-detect without [tool.ruff] skips"
    setup_t3_ruff_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[project]\nname = "x"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_exit "ruff" 0
      mock.activate
    }
    cleanup_t3_ruff_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_t3_ruff_no_cfg'
    After 'cleanup_t3_ruff_no_cfg'

    It "skips Python auto-detect without [tool.ruff]"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no ruff config found"
    End
  End

  Describe "Tier 3: rustfmt auto-detect without rustfmt.toml skips"
    setup_t3_rust_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[package]\nname = "x"\n' > "${TEST_WS}/Cargo.toml"
      mock.create_exit "cargo" 0
      mock.activate
    }
    cleanup_t3_rust_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_t3_rust_no_cfg'
    After 'cleanup_t3_rust_no_cfg'

    It "skips Rust auto-detect without rustfmt.toml"
      When call verify.format.run "$TEST_WS"
      The status should be success
      The stderr should include "no rustfmt config found"
    End
  End
End
