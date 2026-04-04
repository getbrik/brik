Describe "brik run"

  Describe "brik run without subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run
      The status should equal 2
      The stderr should include "requires a subcommand"
    End
  End

  Describe "brik run stage without name"
    It "shows an error message"
      When run script "$BRIK_BIN" run stage
      The status should equal 2
      The stderr should include "requires a stage name"
    End
  End

  Describe "brik run unknown subcommand"
    It "shows an error message"
      When run script "$BRIK_BIN" run foobar
      The status should equal 2
      The stderr should include "unknown run subcommand"
    End
  End

  Describe "brik unknown command"
    It "shows an error and help hint"
      When run script "$BRIK_BIN" foobar
      The status should equal 2
      The stderr should include "unknown command"
      The stderr should include "brik help"
    End
  End

  Describe "brik run stage build --badopt"
    It "shows an error for unknown option"
      When run script "$BRIK_BIN" run stage build --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  Describe "brik run stage build --config"
    setup() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npm: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/node"
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="${WORKSPACE}/brik.yml"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$MOCK_BIN" "$WORKSPACE" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "accepts --config option"
      When run script "$BRIK_BIN" run stage build --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik run stage build"
    setup() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npm: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/node"
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$MOCK_BIN" "$WORKSPACE" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "executes successfully with a node workspace"
      When run script "$BRIK_BIN" run stage build --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage build completed successfully"
    End
  End

  Describe "brik run stage test"
    setup() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npx" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npx: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npx"
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$MOCK_BIN" "$WORKSPACE" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "executes test stage successfully with a node workspace"
      When run script "$BRIK_BIN" run stage test --workspace "$WORKSPACE"
      The status should be success
      The stdout should be present
      The stderr should include "stage test completed successfully"
    End
  End

  Describe "brik run stage init"
    setup() {
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0"}\n' > "${WORKSPACE}/package.json"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "$CONFIG"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$WORKSPACE" "$CONFIG" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "executes init stage successfully"
      When run script "$BRIK_BIN" run stage init --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "cli-test"
      The stderr should include "stage init completed successfully"
    End
  End

  Describe "brik run stage quality"
    setup() {
      WORKSPACE="$(mktemp -d)"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\nquality:\n  enabled: "false"\n' > "$CONFIG"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$WORKSPACE" "$CONFIG" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "executes quality stage successfully"
      When run script "$BRIK_BIN" run stage quality --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "quality"
      The stderr should include "stage quality completed successfully"
    End
  End

  Describe "brik run pipeline"
    setup() {
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npm: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/node"
      cat > "${MOCK_BIN}/npx" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npx: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npx"
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\nquality:\n  enabled: "false"\ntest:\n  framework: npm\n' > "$CONFIG"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
    }
    cleanup() { rm -rf "$MOCK_BIN" "$WORKSPACE" "$CONFIG" "$BRIK_LOG_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "executes the full default pipeline"
      When run script "$BRIK_BIN" run pipeline --workspace "$WORKSPACE" --config "$CONFIG"
      The status should be success
      The stdout should include "Pipeline Summary"
      The stdout should include "PASS"
      The stderr should be present
    End

    It "accepts --with-package flag"
      When run script "$BRIK_BIN" run pipeline --workspace "$WORKSPACE" --config "$CONFIG" --with-package
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End

    It "rejects unknown pipeline flags"
      When run script "$BRIK_BIN" run pipeline --workspace "$WORKSPACE" --config "$CONFIG" --bad-flag
      The status should equal 2
      The stderr should include "unknown"
    End
  End
End
