Describe "deploy/gitops.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/deploy/gitops.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

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
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock git"
      setup_git() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        # Mock git: logs calls and simulates clone by creating the destination directory
        # git clone --depth 1 <repo> <dest> => $1=clone $2=--depth $3=1 $4=<repo> $5=<dest>
        # git -C <dir> diff --cached --quiet => exit 1 to simulate staged changes present
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$5"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "diff" ]; then
    exit 1
  fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git() {
        mock.cleanup
        unset BRIK_TAG BRIK_COMMIT_SHA BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git'
      After 'cleanup_git'

      It "clones repo with --depth 1"
        invoke_clone() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null || return 1
          grep -q "clone --depth 1" "$MOCK_LOG"
        }
        When call invoke_clone
        The status should be success
      End

      It "clones the correct repo URL"
        invoke_repo_url() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null || return 1
          grep -q "https://github.com/org/gitops.git" "$MOCK_LOG"
        }
        When call invoke_repo_url
        The status should be success
      End

      It "commits with a descriptive message containing deploy keyword"
        invoke_commit() {
          export BRIK_TAG="v1.2.3"
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null || return 1
          grep -q "commit" "$MOCK_LOG"
        }
        When call invoke_commit
        The status should be success
      End

      It "pushes to remote"
        invoke_push() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null || return 1
          grep -q "push" "$MOCK_LOG"
        }
        When call invoke_push
        The status should be success
      End

      It "uses BRIK_TAG as image tag when available"
        invoke_tag() {
          export BRIK_TAG="v2.0.0"
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null
          grep -q "v2.0.0" "$MOCK_LOG"
        }
        When call invoke_tag
        The status should be success
      End

      It "falls back to BRIK_COMMIT_SHA when no BRIK_TAG"
        invoke_sha() {
          unset BRIK_TAG 2>/dev/null
          export BRIK_COMMIT_SHA="abc1234"
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null
          grep -q "abc1234" "$MOCK_LOG"
        }
        When call invoke_sha
        The status should be success
      End

      It "does not push in dry-run mode"
        invoke_dryrun_nopush() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" --dry-run 2>/dev/null
          # push should NOT appear in log
          ! grep -q " push" "$MOCK_LOG"
        }
        When call invoke_dryrun_nopush
        The status should be success
      End

      It "still clones and commits in dry-run mode"
        invoke_dryrun_clone() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" --dry-run 2>/dev/null
          grep -q "clone" "$MOCK_LOG"
        }
        When call invoke_dryrun_clone
        The status should be success
      End

      It "logs dry-run message when --dry-run is set"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" --dry-run
        The status should be success
        The stderr should include "dry-run"
      End

      It "supports --controller argocd without app-name and logs argocd message"
        invoke_argocd() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --controller argocd 2>&1 | grep -qi "argocd"
        }
        When call invoke_argocd
        The status should be success
      End

      It "supports --controller fluxcd and logs auto-reconcile message"
        invoke_fluxcd() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --controller fluxcd 2>&1 | grep -qi "flux"
        }
        When call invoke_fluxcd
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
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
        # git mock: clone creates dest dir, diff returns 1 to simulate staged changes
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$5"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "diff" ]; then
    exit 1
  fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        # argocd mock: logs calls and always succeeds
        printf "#!/bin/sh\nprintf 'argocd %%s\\n' \"\$*\" >> \"%s\"\n" "$ARGOCD_LOG" > "${MOCK_BIN}/argocd"
        chmod +x "${MOCK_BIN}/argocd"
        mock.activate
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        # Set BRIK_HOME so brik.use can resolve deploy/argocd.sh
        export BRIK_HOME
      }
      cleanup_git_argocd() {
        mock.cleanup
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_argocd'
      After 'cleanup_git_argocd'

      It "calls argocd app sync after git push when --app-name is set"
        invoke_argocd_sync() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --controller argocd --app-name my-app 2>/dev/null || return 1
          grep -q "app sync my-app" "$ARGOCD_LOG"
        }
        When call invoke_argocd_sync
        The status should be success
      End

      It "calls argocd app wait after sync when --app-name is set"
        invoke_argocd_wait() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --controller argocd --app-name my-app 2>/dev/null || return 1
          grep -q "app wait my-app" "$ARGOCD_LOG"
        }
        When call invoke_argocd_wait
        The status should be success
      End

      It "does not call argocd sync in dry-run mode"
        invoke_argocd_dryrun() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --controller argocd --app-name my-app --dry-run 2>/dev/null
          # argocd sync must NOT appear in log
          ! grep -q "app sync" "$ARGOCD_LOG" 2>/dev/null
        }
        When call invoke_argocd_dryrun
        The status should be success
      End

      It "logs dry-run argocd message when --dry-run is set"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --controller argocd --app-name my-app --dry-run
        The status should be success
        The stderr should include "dry-run"
      End
    End

    Describe "with --path option"
      setup_git_path() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        # git clone --depth 1 <repo> <dest> => $5=<dest>
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$5"
  mkdir -p "\${dest}/k8s/overlays"
fi
for arg; do
  if [ "\$arg" = "diff" ]; then
    exit 1
  fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_path() {
        mock.cleanup
        unset BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_path'
      After 'cleanup_git_path'

      It "supports --path for subdirectory operations"
        invoke_path() {
          deploy.gitops.run --repo "https://github.com/org/gitops.git" \
            --path "k8s/overlays" 2>/dev/null || return 1
          grep -q "clone" "$MOCK_LOG"
        }
        When call invoke_path
        The status should be success
      End
    End

    Describe "with failing git push"
      setup_git_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        # git clone --depth 1 <repo> <dest> => $5=<dest>
        # git -C <dir> diff => exit 1 to simulate staged changes present
        # git -C <dir> push => exit 1 to simulate push failure
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$5"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "diff" ]; then
    exit 1
  fi
done
for arg; do
  if [ "\$arg" = "push" ]; then
    exit 1
  fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_fail() {
        mock.cleanup
        unset BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_fail'
      After 'cleanup_git_fail'

      It "returns 5 when git push fails"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should equal 5
        The stderr should include "git push failed"
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        # git clone --depth 1 <repo> <dest> => $5=<dest>
        # git -C <dir> diff => exit 1 to simulate staged changes present
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$5"
  mkdir -p "\$dest"
fi
for arg; do
  if [ "\$arg" = "diff" ]; then
    exit 1
  fi
done
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
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null
          ! grep -q " push" "$MOCK_LOG"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "path traversal rejection"
      setup_git_traversal() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_traversal() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_traversal'
      After 'cleanup_git_traversal'

      It "returns 2 when --path contains '..'"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" --path "../etc"
        The status should equal 2
        The stderr should include "must not contain"
      End
    End

    Describe "path not found in cloned repo"
      setup_git_nopath() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_nopath() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_nopath'
      After 'cleanup_git_nopath'

      It "returns 6 when --path dir does not exist in clone"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" --path "nonexistent/dir"
        The status should equal 6
        The stderr should include "path not found"
      End
    End

    Describe "git clone failure"
      setup_git_clone_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
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
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should equal 5
        The stderr should include "git clone failed"
      End
    End

    Describe "git add failure"
      setup_git_add_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; exit 0; fi
for arg; do
  if [ "\$arg" = "add" ]; then exit 1; fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_add_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_add_fail'
      After 'cleanup_git_add_fail'

      It "returns 5 when git add fails"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should equal 5
        The stderr should include "git add failed"
      End
    End

    Describe "git commit failure (non-1 exit code)"
      setup_git_commit_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; exit 0; fi
for arg; do
  if [ "\$arg" = "commit" ]; then exit 128; fi
done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_commit_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_commit_fail'
      After 'cleanup_git_commit_fail'

      It "returns 5 when git commit fails with exit code != 1"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should equal 5
        The stderr should include "git commit failed"
      End
    End

    Describe "no changes to commit (exit 1)"
      setup_git_nochange() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; exit 0; fi
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

      It "returns 0 when nothing to commit (git commit exits 1)"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git"
        The status should be success
        The stderr should include "no changes to commit"
      End
    End

    Describe "passthrough options"
      setup_git_passthrough() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; fi
for arg; do if [ "\$arg" = "diff" ]; then exit 1; fi; done
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_git_passthrough() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_git_passthrough'
      After 'cleanup_git_passthrough'

      It "ignores --target and --env passthrough options"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" --target k8s --env staging
        The status should be success
        The stderr should include "gitops deployment completed"
      End
    End

    Describe "BRIK_DEPLOY_IMAGE_TAG precedence"
      setup_git_tag_prio() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; fi
for arg; do if [ "\$arg" = "diff" ]; then exit 1; fi; done
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
          deploy.gitops.run --repo "https://github.com/org/gitops.git" 2>/dev/null
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
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then mkdir -p "\$5"; fi
for arg; do if [ "\$arg" = "diff" ]; then exit 1; fi; done
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
        When call deploy.gitops.run --repo "https://user:secret@github.com/org/gitops.git"
        The status should be success
        The stderr should include "***"
      End
    End

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
End
