# L2 edge: Stack -> Package Manager (graph edge #9)
#
# Each stack drives its language package-manager CLI (npm, cargo, ...) for
# install/build. This pins the dispatch contract: the right tool gets the
# right subcommand/flags. Binaries are mocked so the spec runs without a real
# toolchain.

Describe "L2 stack -> package manager: stacks drive the right PM CLI"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/node.sh"
  Include "$BRIK_STACKS_LIB/rust.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "node -> npm"
    setup_npm() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="$TEST_WS/npm.log"
      printf '{"name":"t"}\n' > "$TEST_WS/package.json"
      printf '{}\n' > "$TEST_WS/package-lock.json"
      mock.create_logging npm "$MOCK_LOG"
      mock.activate
    }
    cleanup_npm() { mock.cleanup; rm -rf "$TEST_WS"; }
    Before 'setup_npm'
    After 'cleanup_npm'

    It "runs npm ci when a lockfile is present"
      check() {
        stacks.node.install "$TEST_WS" 2>/dev/null || return 1
        grep -q "^npm ci" "$MOCK_LOG"
      }
      When call check
      The status should be success
    End
  End

  Describe "rust -> cargo"
    setup_cargo() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="$TEST_WS/cargo.log"
      printf '[package]\nname = "t"\nversion = "0.1.0"\n' > "$TEST_WS/Cargo.toml"
      mock.create_logging cargo "$MOCK_LOG"
      mock.activate
    }
    cleanup_cargo() { mock.cleanup; rm -rf "$TEST_WS"; }
    Before 'setup_cargo'
    After 'cleanup_cargo'

    It "runs cargo build by default"
      check() {
        stacks.rust.build "$TEST_WS" 2>/dev/null || return 1
        grep -q "^cargo build" "$MOCK_LOG"
      }
      When call check
      The status should be success
    End

    It "passes --release with --profile release"
      check() {
        stacks.rust.build "$TEST_WS" --profile release 2>/dev/null || return 1
        grep -q -- "--release" "$MOCK_LOG"
      }
      When call check
      The status should be success
    End
  End
End
