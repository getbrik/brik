Describe "brik run stage"

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

  Describe "brik run stage with unsupported stage"
    It "shows an error message"
      When run script "$BRIK_BIN" run stage deploy
      The status should equal 2
      The stderr should include "unsupported stage"
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
End
