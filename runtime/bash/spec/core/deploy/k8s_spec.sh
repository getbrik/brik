Describe "deploy/k8s.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/k8s.sh"

  Describe "deploy.k8s.run"
    It "returns 2 for unknown option"
      When call deploy.k8s.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 when no manifest specified"
      When call deploy.k8s.run
      The status should equal 2
      The stderr should include "manifest path is required"
    End

    It "returns 6 when manifest file not found"
      When call deploy.k8s.run --manifest "/nonexistent/manifest.yaml"
      The status should equal 6
      The stderr should include "required file not found"
    End

    Describe "require_tool kubectl failure"
      setup_no_kubectl() {
        TEST_WS="$(mktemp -d)"
        printf 'apiVersion: v1\nkind: Pod\n' > "${TEST_WS}/manifest.yaml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_kubectl() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_kubectl'
      After 'cleanup_no_kubectl'

      It "returns 3 when kubectl is not on PATH"
        When call deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock kubectl"
      setup_kubectl() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_kubectl.log"
        printf 'apiVersion: v1\nkind: Pod\n' > "${TEST_WS}/manifest.yaml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/kubectl" << MOCKEOF
#!/usr/bin/env bash
printf 'kubectl %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/kubectl"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_kubectl() {
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_kubectl'
      After 'cleanup_kubectl'

      It "applies manifest with kubectl apply -f"
        invoke_apply() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" 2>/dev/null || return 1
          grep -q "^kubectl apply -f" "$MOCK_LOG"
        }
        When call invoke_apply
        The status should be success
      End

      It "includes manifest path in command"
        invoke_manifest() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" 2>/dev/null || return 1
          grep -q "${TEST_WS}/manifest.yaml" "$MOCK_LOG"
        }
        When call invoke_manifest
        The status should be success
      End

      It "passes namespace option"
        invoke_namespace() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" --namespace production 2>/dev/null || return 1
          grep -q "\-\-namespace production" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "passes context option"
        invoke_context() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" --context my-cluster 2>/dev/null || return 1
          grep -q "\-\-context my-cluster" "$MOCK_LOG"
        }
        When call invoke_context
        The status should be success
      End

      It "uses dry-run mode via --dry-run flag"
        invoke_dryrun() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run=client" "$MOCK_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml"
        The status should be success
        The stderr should include "deployment completed successfully"
      End

      It "combines namespace and context options"
        invoke_combined() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" --namespace staging --context dev-cluster 2>/dev/null || return 1
          grep -q "\-\-namespace staging" "$MOCK_LOG" && grep -q "\-\-context dev-cluster" "$MOCK_LOG"
        }
        When call invoke_combined
        The status should be success
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_kubectl.log"
        printf 'apiVersion: v1\n' > "${TEST_WS}/manifest.yaml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/kubectl" << MOCKEOF
#!/usr/bin/env bash
printf 'kubectl %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/kubectl"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_DRY_RUN="true"
      }
      cleanup_env_dryrun() {
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_env_dryrun'
      After 'cleanup_env_dryrun'

      It "respects BRIK_DRY_RUN env var"
        invoke_env_dryrun() {
          deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml" 2>/dev/null || return 1
          grep -q "\-\-dry-run=client" "$MOCK_LOG"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "with failing kubectl"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf 'apiVersion: v1\n' > "${TEST_WS}/manifest.yaml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/kubectl" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/kubectl"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when kubectl fails"
        When call deploy.k8s.run --manifest "${TEST_WS}/manifest.yaml"
        The status should equal 5
        The stderr should include "kubectl apply failed"
      End
    End
  End
End
