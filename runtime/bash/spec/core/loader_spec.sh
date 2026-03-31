Describe "_loader.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"

  setup() {
    export BRIK_PROJECT_DIR="/nonexistent"
    # Use real BRIK_HOME for standard lib resolution
  }
  Before 'setup'

  Describe "brik.use"
    It "loads a standard library module (version)"
      When call brik.use version
      The status should be success
    End

    Describe "double-load prevention"
      setup_counter() {
        COUNTER_DIR="$(mktemp -d)"
        mkdir -p "${COUNTER_DIR}"
        printf '_TEST_COUNTER=$(( ${_TEST_COUNTER:-0} + 1 ))\n' > "${COUNTER_DIR}/countmod.sh"
        export BRIK_LIB_EXTENSIONS="$COUNTER_DIR"
        export BRIK_PROJECT_DIR="/nonexistent"
        unset _BRIK_MODULE_COUNTMOD_LOADED
        export _TEST_COUNTER=0
      }
      cleanup_counter() {
        rm -rf "$COUNTER_DIR"
        unset _BRIK_MODULE_COUNTMOD_LOADED
        unset _TEST_COUNTER
        unset BRIK_LIB_EXTENSIONS
      }
      Before 'setup_counter'
      After 'cleanup_counter'

      It "sources the module only once even when called twice"
        verify_single_load() {
          brik.use countmod 2>/dev/null
          brik.use countmod 2>/dev/null
          [[ "$_TEST_COUNTER" -eq 1 ]]
        }
        When call verify_single_load
        The status should be success
      End
    End

    It "returns 1 for a nonexistent module"
      When call brik.use __nonexistent_module__
      The status should equal 1
      The stderr should include "module not found"
    End

    It "resolves dot notation (build.node -> build/node.sh)"
      When call brik.use build.node
      The status should be success
    End

    Describe "project extension priority"
      setup_ext() {
        EXT_DIR="$(mktemp -d)"
        mkdir -p "${EXT_DIR}/.brik/lib/core"
        printf '# project override\n_TEST_PROJECT_OVERRIDE=1\n' > "${EXT_DIR}/.brik/lib/core/version.sh"
        export BRIK_PROJECT_DIR="$EXT_DIR"
        # Reset guard to allow re-loading
        unset _BRIK_MODULE_VERSION_LOADED
      }
      cleanup_ext() {
        rm -rf "$EXT_DIR"
        unset _TEST_PROJECT_OVERRIDE
        unset _BRIK_MODULE_VERSION_LOADED
      }
      Before 'setup_ext'
      After 'cleanup_ext'

      It "loads from project extensions first"
        verify_project() {
          brik.use version 2>/dev/null
          [[ "${_TEST_PROJECT_OVERRIDE:-}" == "1" ]]
        }
        When call verify_project
        The status should be success
      End
    End

    Describe "BRIK_LIB_EXTENSIONS resolution"
      setup_org_ext() {
        ORG_EXT_DIR="$(mktemp -d)"
        mkdir -p "${ORG_EXT_DIR}"
        printf '# org extension\n_TEST_ORG_EXTENSION=1\n' > "${ORG_EXT_DIR}/custom_mod.sh"
        export BRIK_LIB_EXTENSIONS="$ORG_EXT_DIR"
        export BRIK_PROJECT_DIR="/nonexistent"
        unset _BRIK_MODULE_CUSTOM_MOD_LOADED
      }
      cleanup_org_ext() {
        rm -rf "$ORG_EXT_DIR"
        unset _TEST_ORG_EXTENSION
        unset _BRIK_MODULE_CUSTOM_MOD_LOADED
        unset BRIK_LIB_EXTENSIONS
      }
      Before 'setup_org_ext'
      After 'cleanup_org_ext'

      It "loads module from BRIK_LIB_EXTENSIONS directory"
        verify_org() {
          brik.use custom_mod 2>/dev/null
          [[ "${_TEST_ORG_EXTENSION:-}" == "1" ]]
        }
        When call verify_org
        The status should be success
      End
    End

    Describe "multiple BRIK_LIB_EXTENSIONS paths"
      setup_multi_ext() {
        EXT_DIR1="$(mktemp -d)"
        EXT_DIR2="$(mktemp -d)"
        mkdir -p "${EXT_DIR2}"
        printf '# ext2 module\n_TEST_MULTI_EXT=2\n' > "${EXT_DIR2}/multi_mod.sh"
        export BRIK_LIB_EXTENSIONS="${EXT_DIR1}:${EXT_DIR2}"
        export BRIK_PROJECT_DIR="/nonexistent"
        unset _BRIK_MODULE_MULTI_MOD_LOADED
      }
      cleanup_multi_ext() {
        rm -rf "$EXT_DIR1" "$EXT_DIR2"
        unset _TEST_MULTI_EXT
        unset _BRIK_MODULE_MULTI_MOD_LOADED
        unset BRIK_LIB_EXTENSIONS
      }
      Before 'setup_multi_ext'
      After 'cleanup_multi_ext'

      It "searches multiple colon-separated paths"
        verify_multi() {
          brik.use multi_mod 2>/dev/null
          [[ "${_TEST_MULTI_EXT:-}" == "2" ]]
        }
        When call verify_multi
        The status should be success
      End
    End

    Describe "source failure"
      setup_bad() {
        BAD_EXT_DIR="$(mktemp -d)"
        mkdir -p "${BAD_EXT_DIR}"
        # Create a file with invalid bash syntax
        printf 'if [[\n' > "${BAD_EXT_DIR}/bad_module.sh"
        export BRIK_LIB_EXTENSIONS="$BAD_EXT_DIR"
        export BRIK_PROJECT_DIR="/nonexistent"
        unset _BRIK_MODULE_BAD_MODULE_LOADED
      }
      cleanup_bad() {
        rm -rf "$BAD_EXT_DIR"
        unset _BRIK_MODULE_BAD_MODULE_LOADED
        unset BRIK_LIB_EXTENSIONS
      }
      Before 'setup_bad'
      After 'cleanup_bad'

      It "returns 1 when module cannot be sourced"
        When call brik.use bad_module
        The status should equal 1
        The stderr should include "failed to source module"
      End
    End
  End
End
