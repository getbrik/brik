Describe "deploy/gitops.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/deploy/gitops.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  # =========================================================================
  # deploy.gitops.render_manifests
  # =========================================================================
  Describe "deploy.gitops.render_manifests"
    It "returns 2 when --source is missing"
      When call deploy.gitops.render_manifests --output /tmp/out --type plain
      The status should equal 2
      The stderr should include "source is required"
    End

    It "returns 2 when --output is missing"
      When call deploy.gitops.render_manifests --source /tmp/src --type plain
      The status should equal 2
      The stderr should include "output is required"
    End

    It "returns 2 when --type is missing"
      When call deploy.gitops.render_manifests --source /tmp/src --output /tmp/out
      The status should equal 2
      The stderr should include "type is required"
    End

    It "returns 2 for unknown option"
      When call deploy.gitops.render_manifests --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when source directory does not exist"
      When call deploy.gitops.render_manifests --source /nonexistent --output /tmp/out --type plain
      The status should equal 6
      The stderr should include "source directory not found"
    End

    Describe "unknown render type"
      setup_type_test() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
      }
      cleanup_type_test() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_type_test'
      After 'cleanup_type_test'

      It "returns 7 for unknown render type"
        When call deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type bogus
        The status should equal 7
        The stderr should include "unknown render type"
      End
    End

    Describe "plain type"
      setup_plain() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        printf 'apiVersion: v1\nkind: ConfigMap\n' > "${TEST_WS}/src/cm.yaml"
      }
      cleanup_plain() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_plain'
      After 'cleanup_plain'

      It "copies files for plain type and outputs path"
        invoke_plain() {
          local result
          result="$(deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type plain 2>/dev/null)" || return 1
          [[ -f "${TEST_WS}/out/cm.yaml" ]] && [[ "$result" == "${TEST_WS}/out" ]]
        }
        When call invoke_plain
        The status should be success
      End
    End

    Describe "dry-run mode"
      setup_dryrun() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
      }
      cleanup_dryrun() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "logs dry-run message without rendering"
        When call deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type plain --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "kustomize type - require_tool failure"
      setup_kust_no_tool() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src" "${TEST_WS}/out"
      }
      cleanup_kust_no_tool() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_kust_no_tool'
      After 'cleanup_kust_no_tool'

      It "returns 3 when kustomize not on PATH"
        invoke_kust_no_tool() {
          # Ensure kustomize is not on PATH (it shouldn't be in CI either)
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type kustomize 2>/dev/null
        }
        When call invoke_kust_no_tool
        The status should equal 3
      End
    End

    Describe "helm_template type - require_tool failure"
      setup_helm_no_tool() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src" "${TEST_WS}/out"
        # Save PATH and set to a restricted one without helm
        _SAVED_PATH="$PATH"
        PATH="/usr/bin:/bin"
      }
      cleanup_helm_no_tool() {
        PATH="$_SAVED_PATH"
        rm -rf "$TEST_WS"
      }
      Before 'setup_helm_no_tool'
      After 'cleanup_helm_no_tool'

      It "returns 3 when helm not on PATH"
        When call deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type helm_template
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End

  # =========================================================================
  # deploy.gitops.push_manifests
  # =========================================================================
  Describe "deploy.gitops.push_manifests"
    It "returns 2 when --repo is missing"
      When call deploy.gitops.push_manifests --branch main --path apps --source /tmp/src --message "test"
      The status should equal 2
      The stderr should include "repo is required"
    End

    It "returns 2 when --branch is missing"
      When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" --path apps --source /tmp/src --message "test"
      The status should equal 2
      The stderr should include "branch is required"
    End

    It "returns 2 when --path is missing"
      When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" --branch main --source /tmp/src --message "test"
      The status should equal 2
      The stderr should include "path is required"
    End

    It "returns 2 when --source is missing"
      When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" --branch main --path apps --message "test"
      The status should equal 2
      The stderr should include "source is required"
    End

    It "returns 2 when --message is missing"
      When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" --branch main --path apps --source /tmp/src
      The status should equal 2
      The stderr should include "message is required"
    End

    It "returns 2 for unknown option"
      When call deploy.gitops.push_manifests --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "require_tool git failure"
      setup_no_git() {
        mock.setup
        mock.isolate
      }
      cleanup_no_git() {
        mock.cleanup
      }
      Before 'setup_no_git'
      After 'cleanup_no_git'

      It "returns 3 when git is not on PATH"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" --branch main --path apps --source /tmp/src --message "test"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock git"
      setup_git() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        printf 'apiVersion: v1\n' > "${TEST_WS}/rendered/deploy.yaml"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git'
      After 'cleanup_git'

      It "clones with --depth 1 --branch"
        invoke_clone() {
          deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
            --branch main --path apps/myapp --source "${TEST_WS}/rendered" \
            --message "deploy" 2>/dev/null || return 1
          grep -q "clone --depth 1 --branch main" "$MOCK_LOG"
        }
        When call invoke_clone
        The status should be success
      End

      It "commits and pushes"
        invoke_push() {
          deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
            --branch main --path apps/myapp --source "${TEST_WS}/rendered" \
            --message "deploy: update" 2>/dev/null || return 1
          grep -q "commit" "$MOCK_LOG" && grep -q "push" "$MOCK_LOG"
        }
        When call invoke_push
        The status should be success
      End

      It "succeeds and logs push completion"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps/myapp --source "${TEST_WS}/rendered" \
          --message "deploy: update"
        The status should be success
        The stderr should include "manifests pushed successfully"
      End

      It "dry-run mode: logs without pushing"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps/myapp --source "${TEST_WS}/rendered" \
          --message "deploy" --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "nothing to commit (git commit exit 1)"
      setup_git_nochange() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "commit" ]; then exit 1; fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_nochange() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_nochange'
      After 'cleanup_git_nochange'

      It "returns 0 when nothing to commit"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" --message "deploy"
        The status should be success
        The stderr should include "no changes to commit"
      End
    End

    Describe "git clone failure"
      setup_git_clone_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${MOCK_BIN}/git" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_clone_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_clone_fail'
      After 'cleanup_git_clone_fail'

      It "returns 5 when git clone fails"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" --message "deploy"
        The status should equal 5
        The stderr should include "git clone failed"
      End
    End

    Describe "git push failure"
      setup_git_push_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "push" ]; then exit 1; fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_push_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_push_fail'
      After 'cleanup_git_push_fail'

      It "returns 5 when git push fails"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" --message "deploy"
        The status should equal 5
        The stderr should include "git push failed"
      End
    End

    Describe "token injection"
      setup_git_token() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
        export MY_GIT_TOKEN="secret-token-123"
      }
      cleanup_git_token() {
        mock.cleanup
        unset MY_GIT_TOKEN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_token'
      After 'cleanup_git_token'

      It "injects token into clone URL"
        invoke_token() {
          deploy.gitops.push_manifests --repo "https://github.com/org/config.git" \
            --branch main --path apps --source "${TEST_WS}/rendered" \
            --message "deploy" --git-token-var MY_GIT_TOKEN 2>/dev/null || return 1
          grep -q "secret-token-123" "$MOCK_LOG"
        }
        When call invoke_token
        The status should be success
      End

      It "masks token in log messages"
        When call deploy.gitops.push_manifests --repo "https://github.com/org/config.git" \
          --branch main --path apps --source "${TEST_WS}/rendered" \
          --message "deploy" --git-token-var MY_GIT_TOKEN
        The status should be success
        The stderr should include "***"
      End
    End

    Describe "missing token variable"
      setup_git_no_token() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
        unset EMPTY_TOKEN_VAR 2>/dev/null
      }
      cleanup_git_no_token() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_no_token'
      After 'cleanup_git_no_token'

      It "returns 4 when token variable is empty"
        When call deploy.gitops.push_manifests --repo "https://github.com/org/config.git" \
          --branch main --path apps --source "${TEST_WS}/rendered" \
          --message "deploy" --git-token-var EMPTY_TOKEN_VAR
        The status should equal 4
        The stderr should include "token variable is empty"
      End
    End
  End

  # =========================================================================
  # deploy.gitops.wait_sync
  # =========================================================================
  Describe "deploy.gitops.wait_sync"
    It "returns 2 when --check-fn is missing"
      When call deploy.gitops.wait_sync
      The status should equal 2
      The stderr should include "check-fn is required"
    End

    It "returns 2 when check-fn is not a declared function"
      When call deploy.gitops.wait_sync --check-fn "nonexistent_function"
      The status should equal 2
      The stderr should include "not a declared function"
    End

    It "returns 2 for unknown option"
      When call deploy.gitops.wait_sync --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for non-integer timeout"
      _mock_check() { return 0; }
      When call deploy.gitops.wait_sync --check-fn "_mock_check" --timeout "abc"
      The status should equal 2
      The stderr should include "timeout must be a positive integer"
    End

    It "returns 2 for invalid interval"
      _mock_check2() { return 0; }
      When call deploy.gitops.wait_sync --check-fn "_mock_check2" --interval 0
      The status should equal 2
      The stderr should include "interval must be a positive integer"
    End

    Describe "successful sync"
      It "returns 0 when check-fn succeeds immediately"
        _mock_sync_ok() { return 0; }
        invoke_sync_ok() {
          deploy.gitops.wait_sync --check-fn "_mock_sync_ok" --timeout 5 --interval 1 2>/dev/null
        }
        When call invoke_sync_ok
        The status should be success
      End
    End

    Describe "timeout"
      It "returns 8 when check-fn never succeeds"
        _mock_sync_fail() { return 1; }
        When call deploy.gitops.wait_sync --check-fn "_mock_sync_fail" --timeout 2 --interval 1
        The status should equal 8
        The stderr should include "sync timeout"
      End
    End

    Describe "dry-run mode"
      It "logs dry-run message"
        _mock_sync_dr() { return 0; }
        When call deploy.gitops.wait_sync --check-fn "_mock_sync_dr" --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.gitops.diff
  # =========================================================================
  Describe "deploy.gitops.diff"
    It "returns 2 when --repo is missing"
      When call deploy.gitops.diff --branch main --path apps --source /tmp/src
      The status should equal 2
      The stderr should include "repo is required"
    End

    It "returns 2 when --branch is missing"
      When call deploy.gitops.diff --repo "https://git.example.com/repo" --path apps --source /tmp/src
      The status should equal 2
      The stderr should include "branch is required"
    End

    It "returns 2 when --path is missing"
      When call deploy.gitops.diff --repo "https://git.example.com/repo" --branch main --source /tmp/src
      The status should equal 2
      The stderr should include "path is required"
    End

    It "returns 2 when --source is missing"
      When call deploy.gitops.diff --repo "https://git.example.com/repo" --branch main --path apps
      The status should equal 2
      The stderr should include "source is required"
    End

    Describe "require_tool git failure"
      setup_no_git_diff() {
        mock.setup
        mock.isolate
      }
      cleanup_no_git_diff() {
        mock.cleanup
      }
      Before 'setup_no_git_diff'
      After 'cleanup_no_git_diff'

      It "returns 3 when git is not on PATH"
        When call deploy.gitops.diff --repo "https://git.example.com/repo" --branch main --path apps --source /tmp/src
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End

  # =========================================================================
  # deploy.gitops.rollback
  # =========================================================================
  Describe "deploy.gitops.rollback"
    It "returns 2 when --repo is missing"
      When call deploy.gitops.rollback --branch main
      The status should equal 2
      The stderr should include "repo is required"
    End

    It "returns 2 when --branch is missing"
      When call deploy.gitops.rollback --repo "https://git.example.com/repo"
      The status should equal 2
      The stderr should include "branch is required"
    End

    It "returns 2 for unknown option"
      When call deploy.gitops.rollback --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "require_tool git failure"
      setup_no_git_rb() {
        mock.setup
        mock.isolate
      }
      cleanup_no_git_rb() {
        mock.cleanup
      }
      Before 'setup_no_git_rb'
      After 'cleanup_no_git_rb'

      It "returns 3 when git is not on PATH"
        When call deploy.gitops.rollback --repo "https://git.example.com/repo" --branch main
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "dry-run mode"
      setup_rb_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "git" 0
        mock.activate
      }
      cleanup_rb_dryrun() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rb_dryrun'
      After 'cleanup_rb_dryrun'

      It "logs dry-run message"
        When call deploy.gitops.rollback --repo "https://git.example.com/repo" --branch main --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End
  End

  # =========================================================================
  # deploy.gitops.run (orchestrator)
  # =========================================================================
  Describe "deploy.gitops.run"
    It "returns 2 for unknown option"
      When call deploy.gitops.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 when --repo is missing"
      When call deploy.gitops.run
      The status should equal 2
      The stderr should include "repo is required"
    End

    Describe "with mock git"
      setup_git_run() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/src"
        printf 'apiVersion: v1\n' > "${TEST_WS}/src/cm.yaml"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_run() {
        mock.cleanup
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA BRIK_DEPLOY_IMAGE_TAG 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_run'
      After 'cleanup_git_run'

      It "pushes to remote via push_manifests"
        invoke_run_push() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" 2>/dev/null || return 1
          grep -q "push" "$MOCK_LOG"
        }
        When call invoke_run_push
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src"
        The status should be success
        The stderr should include "gitops deployment completed"
      End

      It "does not push in dry-run mode"
        invoke_run_dryrun() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" --dry-run 2>/dev/null
          ! grep -q "push" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_run_dryrun
        The status should be success
      End

      It "logs dry-run message when --dry-run is set"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src" --dry-run
        The status should be success
        The stderr should include "dry-run"
      End

      It "supports --controller fluxcd and logs auto-reconcile message"
        invoke_fluxcd() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" --controller fluxcd 2>&1 | grep -qi "flux"
        }
        When call invoke_fluxcd
        The status should be success
      End

      It "ignores --target and --env passthrough options"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src" --target k8s --env staging
        The status should be success
        The stderr should include "gitops deployment completed"
      End
    End

    Describe "with --controller argocd and --app-name"
      setup_git_argocd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        ARGOCD_LOG="${TEST_WS}/mock_argocd.log"
        mkdir -p "${TEST_WS}/src"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        printf "#!/bin/sh\nprintf 'argocd %%s\\n' \"\$*\" >> \"%s\"\n" "$ARGOCD_LOG" > "${MOCK_BIN}/argocd"
        chmod +x "${MOCK_BIN}/argocd"
        mock.activate
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        export BRIK_HOME
      }
      cleanup_git_argocd() {
        mock.cleanup
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_argocd'
      After 'cleanup_git_argocd'

      It "calls argocd app sync after push when --app-name is set"
        invoke_argocd_sync() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" --controller argocd --app-name my-app 2>/dev/null || return 1
          grep -q "app sync" "$ARGOCD_LOG"
        }
        When call invoke_argocd_sync
        The status should be success
      End

      It "calls argocd app wait after sync when --app-name is set"
        invoke_argocd_wait() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" --controller argocd --app-name my-app 2>/dev/null || return 1
          grep -q "app wait" "$ARGOCD_LOG"
        }
        When call invoke_argocd_wait
        The status should be success
      End

      It "does not call argocd sync in dry-run mode"
        invoke_argocd_dryrun() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" --controller argocd --app-name my-app --dry-run 2>/dev/null
          ! grep -q "app sync" "$ARGOCD_LOG" 2>/dev/null
        }
        When call invoke_argocd_dryrun
        The status should be success
      End

      It "logs dry-run argocd message when --dry-run is set"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src" --controller argocd --app-name my-app --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "BRIK_DEPLOY_IMAGE_TAG precedence"
      setup_git_tag_prio() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/src"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
        export BRIK_DEPLOY_IMAGE_TAG="deploy-tag-1.0"
        export BRIK_TAG="brik-tag-2.0"
      }
      cleanup_git_tag_prio() {
        mock.cleanup
        unset BRIK_DEPLOY_IMAGE_TAG BRIK_TAG 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_tag_prio'
      After 'cleanup_git_tag_prio'

      It "uses BRIK_DEPLOY_IMAGE_TAG over BRIK_TAG when both set"
        invoke_tag_prio() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" 2>/dev/null
          grep -q "deploy-tag-1.0" "$MOCK_LOG"
        }
        When call invoke_tag_prio
        The status should be success
      End
    End

    Describe "credential masking in repo URL"
      setup_git_cred() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/src"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_cred() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_cred'
      After 'cleanup_git_cred'

      It "masks credentials in log output"
        When call deploy.gitops.run --repo "https://user:secret@github.com/org/gitops.git" \
          --source "${TEST_WS}/src"
        The status should be success
        The stderr should include "***"
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/src"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
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

      It "respects BRIK_DRY_RUN env var and does not push"
        invoke_env_dryrun() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --source "${TEST_WS}/src" 2>/dev/null
          ! grep -q "push" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End
  End

  # =========================================================================
  # double-sourcing guard
  # =========================================================================
  Describe "double-sourcing guard"
    It "is callable after double include"
      double_include() {
        # shellcheck source=/dev/null
        . "$BRIK_CORE_LIB/deploy/gitops.sh"
        declare -f deploy.gitops.run >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
