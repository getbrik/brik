Describe "brik integrate --release / --tag (local release context)"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

    # The CI adapters enter release context by setting BRIK_COMMIT_TAG from a
    # tag-push event. The local CLI exposes that intent as --release/--tag: the
    # verb resolves the release tag (HEAD tag, or --tag override) and sets
    # BRIK_COMMIT_TAG so the planner and stages resolve context=release.
    setup() {
      export BRIK_LOCAL_CONTAINER=1
      mock.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.create_script "npx" 'echo "mock npx: $*"'
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      # Release context runs the full flow (signing/evidence), so a referential
      # is mandatory at init.
      mock.infra.setup
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      CONFIG="$(mktemp)"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\nrelease:\n  strategy: semver\n  tag_prefix: v\ntest:\n  framework: npm\n' > "$CONFIG"
    }
    cleanup() {
      mock.infra.teardown
      mock.cleanup
      rm -rf "$WORKSPACE" "$CONFIG"
    }
    Before 'setup'
    After 'cleanup'

    It "rejects --release when the workspace has no tag at HEAD and no --tag"
      # The mktemp workspace is not a tagged git work tree, so there is no
      # release tag to derive: the verb must fail closed rather than run a
      # release with an empty version.
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --config "$CONFIG" --release
      The status should equal 2
      The stderr should include "tag"
    End

    It "accepts --release --tag and runs in release context"
      # --tag supplies the release version explicitly, so the planner resolves
      # context=release and the release stage is included without an opt-in flag.
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --config "$CONFIG" --release --tag v9.9.9
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End
End
