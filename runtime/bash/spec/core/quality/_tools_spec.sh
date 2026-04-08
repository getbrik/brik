Describe "quality/_tools.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/quality/_tools.sh"

  Describe "quality.tool.register + quality.tool.resolve"
    setup_tools() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/grype" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/grype"
      cat > "${MOCK_BIN}/dockle" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/dockle"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_tools() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN"
      # Clean up registry vars
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_tools'
    After 'cleanup_tools'

    It "resolves highest-priority tool"
      invoke_resolve() {
        quality.tool.register testcat grype grype "grype {image}" 10
        quality.tool.register testcat dockle dockle "dockle {image}" 20
        quality.tool.resolve testcat
      }
      When call invoke_resolve
      The output should equal "grype"
      The status should be success
    End

    It "resolves lower-priority tool when higher not available"
      invoke_fallback() {
        # Register a tool whose binary doesn't exist
        quality.tool.register testcat2 missing missing_bin "missing {x}" 10
        quality.tool.register testcat2 dockle dockle "dockle {x}" 20
        quality.tool.resolve testcat2
      }
      When call invoke_fallback
      The output should equal "dockle"
      The status should be success
    End
  End

  Describe "Tier 1: command override"
    setup_cmd() {
      MOCK_BIN="$(mktemp -d)"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_QUALITY_MYCAT_COMMAND="echo hello"
    }
    cleanup_cmd() {
      export PATH="$ORIG_PATH"
      unset BRIK_QUALITY_MYCAT_COMMAND
      rm -rf "$MOCK_BIN"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_cmd'
    After 'cleanup_cmd'

    It "resolves to __command__ when env command is set"
      invoke_tier1() {
        quality.tool.register mycat sometool sometool "sometool" 10
        quality.tool.resolve mycat
      }
      When call invoke_tier1
      The output should equal "__command__"
      The status should be success
    End
  End

  Describe "Tier 2: explicit tool selection"
    setup_tier2() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/dockle" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/dockle"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_tier2() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_tier2'
    After 'cleanup_tier2'

    It "resolves explicit --tool even if not highest priority"
      invoke_explicit() {
        quality.tool.register tier2cat grype grype "grype {x}" 10
        quality.tool.register tier2cat dockle dockle "dockle {x}" 20
        quality.tool.resolve tier2cat --tool dockle
      }
      When call invoke_explicit
      The output should equal "dockle"
      The status should be success
    End
  End

  Describe "no tool available"
    setup_none() {
      MOCK_BIN="$(mktemp -d)"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}"
    }
    cleanup_none() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_none'
    After 'cleanup_none'

    It "returns 1 when no tool is available"
      invoke_none() {
        quality.tool.register nocat missing1 missing1 "cmd1" 10
        quality.tool.register nocat missing2 missing2 "cmd2" 20
        quality.tool.resolve nocat
      }
      When call invoke_none
      The status should equal 1
    End
  End

  Describe "explicit tool missing returns 3"
    setup_missing() {
      MOCK_BIN="$(mktemp -d)"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}"
    }
    cleanup_missing() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_missing'
    After 'cleanup_missing'

    It "returns 3 when explicit tool binary is not found"
      invoke_missing() {
        quality.tool.register misscat grype grype "grype {x}" 10
        quality.tool.resolve misscat --tool grype
      }
      When call invoke_missing
      The status should equal 3
    End
  End

  Describe "unknown tool returns 7"
    setup_unknown() {
      MOCK_BIN="$(mktemp -d)"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_unknown() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_unknown'
    After 'cleanup_unknown'

    It "returns 7 when explicit tool is not registered"
      invoke_unknown() {
        quality.tool.register unkcat grype grype "grype {x}" 10
        quality.tool.resolve unkcat --tool nonexistent
      }
      When call invoke_unknown
      The status should equal 7
    End
  End

  Describe "quality.tool.exec"
    setup_exec() {
      MOCK_BIN="$(mktemp -d)"
      TEST_LOG="$(mktemp)"
      cat > "${MOCK_BIN}/grype" << MOCKEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEST_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/grype"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_exec() {
      export PATH="$ORIG_PATH"
      rm -rf "$MOCK_BIN" "$TEST_LOG"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_exec'
    After 'cleanup_exec'

    It "substitutes {var} placeholders and executes"
      invoke_exec() {
        quality.tool.register execcat grype grype "grype {image} --fail-on {severity}" 10
        quality.tool.exec execcat grype image="myapp:1.0" severity="high" 2>/dev/null || return 1
        grep -q "myapp:1.0" "$TEST_LOG" && grep -q "high" "$TEST_LOG"
      }
      When call invoke_exec
      The status should be success
    End
  End

  Describe "quality.tool.exec with command override"
    setup_cmd_exec() {
      MOCK_BIN="$(mktemp -d)"
      TEST_LOG="$(mktemp)"
      cat > "${MOCK_BIN}/my-scanner" << MOCKEOF
#!/usr/bin/env bash
printf 'my-scanner ran\n' > "$TEST_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/my-scanner"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_QUALITY_CMDCAT_COMMAND="my-scanner"
    }
    cleanup_cmd_exec() {
      export PATH="$ORIG_PATH"
      unset BRIK_QUALITY_CMDCAT_COMMAND
      rm -rf "$MOCK_BIN" "$TEST_LOG"
      for v in $(compgen -v _BRIK_TOOL_ 2>/dev/null); do unset "$v"; done
      _BRIK_TOOL_COUNTER=0
    }
    Before 'setup_cmd_exec'
    After 'cleanup_cmd_exec'

    It "executes command override directly"
      invoke_cmd_exec() {
        quality.tool.exec cmdcat "__command__" 2>/dev/null || return 1
        grep -q "my-scanner ran" "$TEST_LOG"
      }
      When call invoke_cmd_exec
      The status should be success
    End
  End
End
