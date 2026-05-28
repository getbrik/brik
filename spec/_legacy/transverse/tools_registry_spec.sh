Describe "transverse/tools.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/tools.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  Describe "transverse.tools.register + transverse.tools.resolve"
    setup_tools() {
      mock.setup
      mock.create_exit "grype" 0
      mock.create_exit "dockle" 0
      mock.activate
    }
    cleanup_tools() {
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_tools'
    After 'cleanup_tools'

    It "resolves highest-priority tool"
      invoke_resolve() {
        transverse.tools.register testcat grype grype "grype {image}" 10
        transverse.tools.register testcat dockle dockle "dockle {image}" 20
        transverse.tools.resolve testcat
      }
      When call invoke_resolve
      The output should equal "grype"
      The status should be success
    End

    It "resolves lower-priority tool when higher not available"
      invoke_fallback() {
        transverse.tools.register testcat2 missing missing_bin "missing {x}" 10
        transverse.tools.register testcat2 dockle dockle "dockle {x}" 20
        transverse.tools.resolve testcat2
      }
      When call invoke_fallback
      The output should equal "dockle"
      The status should be success
    End
  End

  Describe "Tier 1: command override"
    setup_cmd() {
      mock.setup
      mock.activate
      export BRIK_QUALITY_MYCAT_COMMAND="echo hello"
    }
    cleanup_cmd() {
      unset BRIK_QUALITY_MYCAT_COMMAND
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_cmd'
    After 'cleanup_cmd'

    It "resolves to __command__ when env command is set"
      invoke_tier1() {
        transverse.tools.register mycat sometool sometool "sometool" 10
        transverse.tools.resolve mycat
      }
      When call invoke_tier1
      The output should equal "__command__"
      The status should be success
    End
  End

  Describe "Tier 2: explicit tool selection"
    setup_tier2() {
      mock.setup
      mock.create_exit "dockle" 0
      mock.activate
    }
    cleanup_tier2() {
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_tier2'
    After 'cleanup_tier2'

    It "resolves explicit --tool even if not highest priority"
      invoke_explicit() {
        transverse.tools.register tier2cat grype grype "grype {x}" 10
        transverse.tools.register tier2cat dockle dockle "dockle {x}" 20
        transverse.tools.resolve tier2cat --tool dockle
      }
      When call invoke_explicit
      The output should equal "dockle"
      The status should be success
    End
  End

  Describe "no tool available"
    setup_none() {
      mock.setup
      mock.isolate
    }
    cleanup_none() {
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_none'
    After 'cleanup_none'

    It "returns 1 when no tool is available"
      invoke_none() {
        transverse.tools.register nocat missing1 missing1 "cmd1" 10
        transverse.tools.register nocat missing2 missing2 "cmd2" 20
        transverse.tools.resolve nocat
      }
      When call invoke_none
      The status should equal 1
    End
  End

  Describe "explicit tool missing returns 3"
    setup_missing() {
      mock.setup
      mock.isolate
    }
    cleanup_missing() {
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_missing'
    After 'cleanup_missing'

    It "returns 3 when explicit tool binary is not found"
      invoke_missing() {
        transverse.tools.register misscat grype grype "grype {x}" 10
        transverse.tools.resolve misscat --tool grype
      }
      When call invoke_missing
      The status should equal 3
    End
  End

  Describe "unknown tool returns 7"
    setup_unknown() {
      mock.setup
      mock.activate
    }
    cleanup_unknown() {
      mock.cleanup
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_unknown'
    After 'cleanup_unknown'

    It "returns 7 when explicit tool is not registered"
      invoke_unknown() {
        transverse.tools.register unkcat grype grype "grype {x}" 10
        transverse.tools.resolve unkcat --tool nonexistent
      }
      When call invoke_unknown
      The status should equal 7
    End
  End

  Describe "transverse.tools.exec"
    setup_exec() {
      mock.setup
      TEST_LOG="$(mktemp)"
      mock.create_script "grype" "printf '%s\n' \"\$*\" > \"$TEST_LOG\"
exit 0"
      mock.activate
    }
    cleanup_exec() {
      mock.cleanup
      rm -f "$TEST_LOG"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_exec'
    After 'cleanup_exec'

    It "substitutes {var} placeholders and executes"
      invoke_exec() {
        transverse.tools.register execcat grype grype "grype {image} --fail-on {severity}" 10
        transverse.tools.exec execcat grype image="myapp:1.0" severity="high" 2>/dev/null || return 1
        grep -q "myapp:1.0" "$TEST_LOG" && grep -q "high" "$TEST_LOG"
      }
      When call invoke_exec
      The status should be success
    End
  End

  Describe "transverse.tools.exec with command override"
    setup_cmd_exec() {
      mock.setup
      TEST_LOG="$(mktemp)"
      mock.create_script "my-scanner" "printf 'my-scanner ran\n' > \"$TEST_LOG\"
exit 0"
      mock.activate
      export BRIK_QUALITY_CMDCAT_COMMAND="my-scanner"
    }
    cleanup_cmd_exec() {
      unset BRIK_QUALITY_CMDCAT_COMMAND
      mock.cleanup
      rm -f "$TEST_LOG"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_cmd_exec'
    After 'cleanup_cmd_exec'

    It "executes command override directly"
      invoke_cmd_exec() {
        transverse.tools.exec cmdcat "__command__" 2>/dev/null || return 1
        grep -q "my-scanner ran" "$TEST_LOG"
      }
      When call invoke_cmd_exec
      The status should be success
    End
  End
End
