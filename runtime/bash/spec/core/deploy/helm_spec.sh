Describe "deploy/helm.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/helm.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "deploy.helm.run"
    It "returns 2 for unknown option"
      When call deploy.helm.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 when --chart is missing"
      When call deploy.helm.run
      The status should equal 2
      The stderr should include "chart is required"
    End

    Describe "require_tool helm failure"
      setup_no_helm() {
        mock.setup
        mock.isolate
      }
      cleanup_no_helm() {
        mock.cleanup
      }
      Before 'setup_no_helm'
      After 'cleanup_no_helm'

      It "returns 3 when helm is not on PATH"
        When call deploy.helm.run --chart "my-app/my-chart"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock helm"
      setup_helm() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_helm.log"
        mock.create_logging "helm" "$MOCK_LOG"
        mock.activate
      }
      cleanup_helm() {
        mock.cleanup
        unset BRIK_TAG BRIK_COMMIT_SHA BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_helm'
      After 'cleanup_helm'

      It "runs helm upgrade --install"
        invoke_upgrade() {
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          grep -q "upgrade --install" "$MOCK_LOG"
        }
        When call invoke_upgrade
        The status should be success
      End

      It "includes chart path in command"
        invoke_chart() {
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          grep -q "my-app/my-chart" "$MOCK_LOG"
        }
        When call invoke_chart
        The status should be success
      End

      It "uses --release-name when provided"
        invoke_release() {
          deploy.helm.run --chart "my-app/my-chart" --release-name "my-release" 2>/dev/null || return 1
          grep -q "my-release" "$MOCK_LOG"
        }
        When call invoke_release
        The status should be success
      End

      It "derives release name from chart when not provided"
        invoke_derived() {
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          # When no --release-name, it should use the chart basename (my-chart)
          grep -q "my-chart" "$MOCK_LOG"
        }
        When call invoke_derived
        The status should be success
      End

      It "passes --namespace when set"
        invoke_namespace() {
          deploy.helm.run --chart "my-app/my-chart" --namespace production 2>/dev/null || return 1
          grep -q "\-\-namespace production" "$MOCK_LOG"
        }
        When call invoke_namespace
        The status should be success
      End

      It "passes --values when set"
        invoke_values() {
          local values_file="${TEST_WS}/values.yaml"
          touch "$values_file"
          deploy.helm.run --chart "my-app/my-chart" --values "$values_file" 2>/dev/null || return 1
          grep -q "\-\-values ${values_file}" "$MOCK_LOG"
        }
        When call invoke_values
        The status should be success
      End

      It "sets image.tag from BRIK_TAG"
        invoke_brik_tag() {
          export BRIK_TAG="v1.5.0"
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          grep -q "image.tag=v1.5.0" "$MOCK_LOG"
        }
        When call invoke_brik_tag
        The status should be success
      End

      It "falls back to BRIK_COMMIT_SHA when no BRIK_TAG"
        invoke_sha() {
          unset BRIK_TAG 2>/dev/null
          export BRIK_COMMIT_SHA="deadbeef"
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          grep -q "image.tag=deadbeef" "$MOCK_LOG"
        }
        When call invoke_sha
        The status should be success
      End

      It "passes --dry-run flag when dry-run mode is active"
        invoke_dryrun() {
          deploy.helm.run --chart "my-app/my-chart" --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.helm.run --chart "my-app/my-chart"
        The status should be success
        The stderr should include "helm deployment completed"
      End

      It "combines namespace and values options"
        invoke_combined() {
          local values_file="${TEST_WS}/values-staging.yaml"
          touch "$values_file"
          deploy.helm.run --chart "my-app/my-chart" \
            --namespace staging --values "$values_file" 2>/dev/null || return 1
          grep -q "\-\-namespace staging" "$MOCK_LOG" && grep -q "\-\-values ${values_file}" "$MOCK_LOG"
        }
        When call invoke_combined
        The status should be success
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_helm.log"
        mock.create_logging "helm" "$MOCK_LOG"
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_env_dryrun() {
        mock.cleanup
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_env_dryrun'
      After 'cleanup_env_dryrun'

      It "respects BRIK_DRY_RUN env var"
        invoke_env_dryrun() {
          deploy.helm.run --chart "my-app/my-chart" 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "with failing helm"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "helm" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        unset BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when helm fails"
        When call deploy.helm.run --chart "my-app/my-chart"
        The status should equal 5
        The stderr should include "helm upgrade failed"
      End
    End

    Describe "release name derivation from BRIK_DEPLOY env vars"
      setup_env_release() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_helm.log"
        mock.create_logging "helm" "$MOCK_LOG"
        mock.activate
        export BRIK_DEPLOY_PRODUCTION_RELEASE_NAME="prod-release"
      }
      cleanup_env_release() {
        mock.cleanup
        unset BRIK_DEPLOY_PRODUCTION_RELEASE_NAME BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_env_release'
      After 'cleanup_env_release'

      It "uses BRIK_DEPLOY_{ENV}_RELEASE_NAME when --env is set and no --release-name"
        invoke_env_release() {
          deploy.helm.run --chart "my-app/my-chart" --env production 2>/dev/null || return 1
          grep -q "prod-release" "$MOCK_LOG"
        }
        When call invoke_env_release
        The status should be success
      End
    End

    Describe "double-sourcing guard"
      It "is callable after double include"
        double_include() {
          # shellcheck source=/dev/null
          . "$BRIK_CORE_LIB/deploy/helm.sh"
          declare -f deploy.helm.run >/dev/null && echo "ok" || echo "missing"
        }
        When call double_include
        The output should equal "ok"
      End
    End
  End
End
