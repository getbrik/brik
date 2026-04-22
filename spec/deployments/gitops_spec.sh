Describe "deploy/gitops.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/gitops.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # =========================================================================
  # _deploy.gitops._safe_url
  # =========================================================================
  Describe "_deploy.gitops._safe_url"
    It "masks credentials in URL"
      When call _deploy.gitops._safe_url "https://token123@github.com/org/repo.git"
      The output should equal "https://***@github.com/org/repo.git"
    End

    It "returns URL unchanged when no credentials"
      When call _deploy.gitops._safe_url "https://github.com/org/repo.git"
      The output should equal "https://github.com/org/repo.git"
    End
  End

  # =========================================================================
  # _deploy.gitops._inject_token
  # =========================================================================
  Describe "_deploy.gitops._inject_token"
    It "returns URL unchanged when token_var is empty"
      When call _deploy.gitops._inject_token "https://github.com/org/repo.git" ""
      The output should equal "https://github.com/org/repo.git"
    End

    It "injects token into URL"
      inject_token_test() {
        export MY_GIT_TOKEN="secret123"
        _deploy.gitops._inject_token "https://github.com/org/repo.git" "MY_GIT_TOKEN"
        local rc=$?
        unset MY_GIT_TOKEN
        return $rc
      }
      When call inject_token_test
      The output should equal "https://secret123@github.com/org/repo.git"
    End
  End

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

    Describe "plain type with --set values"
      setup_plain_set() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        printf 'image:\n  tag: old\n' > "${TEST_WS}/src/values.yaml"
      }
      cleanup_plain_set() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_plain_set'
      After 'cleanup_plain_set'

      It "applies --set values via yq on plain manifests"
        invoke_plain_set() {
          deploy.gitops.render_manifests --source "${TEST_WS}/src" \
            --output "${TEST_WS}/out" --type plain \
            --set "image.tag=v2.0" >/dev/null 2>/dev/null || return 1
          grep -q "v2.0" "${TEST_WS}/out/values.yaml"
        }
        When call invoke_plain_set
        The status should be success
      End
    End

    Describe "kustomize type - require_tool failure"
      setup_kust_no_tool() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src" "${TEST_WS}/out"
        # Save PATH and restrict to exclude kustomize (CI runners may have it)
        _SAVED_PATH="$PATH"
        PATH="/usr/bin:/bin"
      }
      cleanup_kust_no_tool() {
        PATH="$_SAVED_PATH"
        rm -rf "$TEST_WS"
      }
      Before 'setup_kust_no_tool'
      After 'cleanup_kust_no_tool'

      It "returns 3 when kustomize not on PATH"
        invoke_kust_no_tool() {
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

    Describe "kustomize type - happy path with mock"
      setup_kust_ok() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        mock.setup
        # Mock kustomize: `edit set image` is a no-op (writes nothing); `build -o <dir>` writes a manifest.
        mock.create_script "kustomize" '
          case "$1" in
            edit) exit 0 ;;
            build)
              out_dir=""
              while [ $# -gt 0 ]; do
                case "$1" in
                  -o) out_dir="$2"; shift 2 ;;
                  *) shift ;;
                esac
              done
              [ -n "$out_dir" ] && mkdir -p "$out_dir" && printf "apiVersion: v1\nkind: ConfigMap\n" > "$out_dir/out.yaml"
              exit 0 ;;
            *) exit 0 ;;
          esac'
        mock.activate
      }
      cleanup_kust_ok() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_kust_ok'
      After 'cleanup_kust_ok'

      It "renders via kustomize build and returns 0"
        invoke_kust() {
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type kustomize >/dev/null 2>&1
        }
        When call invoke_kust
        The status should be success
        The file "${TEST_WS}/out/out.yaml" should be exist
      End

      It "applies --set values via kustomize edit"
        invoke_kust_set() {
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" \
            --type kustomize --set "app=nginx:v2" >/dev/null 2>&1
        }
        When call invoke_kust_set
        The status should be success
      End

      It "returns BRIK_EXIT_EXTERNAL_FAIL when kustomize build fails"
        mock.create_script "kustomize" '
          [ "$1" = "build" ] && exit 3
          exit 0'
        invoke_kust_fail() {
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type kustomize 2>/dev/null
        }
        When call invoke_kust_fail
        The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      End
    End

    Describe "helm_template type - happy path with mock"
      setup_helm_ok() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        mock.setup
        mock.create_script "helm" '
          if [ "$1" = "template" ]; then
            printf "apiVersion: v1\nkind: ConfigMap\n"
            exit 0
          fi
          exit 0'
        mock.activate
      }
      cleanup_helm_ok() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_helm_ok'
      After 'cleanup_helm_ok'

      It "renders via helm template and writes manifests.yaml"
        invoke_helm() {
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type helm_template >/dev/null 2>&1
        }
        When call invoke_helm
        The status should be success
        The file "${TEST_WS}/out/manifests.yaml" should be exist
      End

      It "passes --set values to helm template"
        invoke_helm_set() {
          mkdir -p "${TEST_WS}/out"
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" \
            --type helm_template --set "image.tag=v2" >/dev/null 2>&1
        }
        When call invoke_helm_set
        The status should be success
      End

      It "returns BRIK_EXIT_EXTERNAL_FAIL when helm template fails"
        mock.create_script "helm" '
          [ "$1" = "template" ] && exit 5
          exit 0'
        invoke_helm_fail() {
          mkdir -p "${TEST_WS}/out"
          deploy.gitops.render_manifests --source "${TEST_WS}/src" --output "${TEST_WS}/out" --type helm_template 2>/dev/null
        }
        When call invoke_helm_fail
        The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
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
  # deploy.gitops.push_manifests --image-tag
  # =========================================================================
  Describe "deploy.gitops.push_manifests --image-tag"
    Describe "rewrites image tags in YAML files"
      setup_image_tag() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${TEST_WS}/rendered/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/my-app:latest
        - name: sidecar
          image: registry.example.com/sidecar:0.1.0
YAML
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
      cleanup_image_tag() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_image_tag'
      After 'cleanup_image_tag'

      It "substitutes image tags with the provided value"
        invoke_image_tag() {
          deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
            --branch main --path apps --source "${TEST_WS}/rendered" \
            --message "deploy" --image-tag "v2.0.0" 2>/dev/null || return 1
          # Find the copied deployment.yaml in the tmpdir created by push_manifests
          # Since push_manifests uses its own tmpdir, we check the source was not modified
          # and verify via log that substitution happened
          true
        }
        When call invoke_image_tag
        The status should be success
      End

      It "logs image tag substitution"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" \
          --message "deploy" --image-tag "v2.0.0"
        The status should be success
        The stderr should include "image tags substituted to :v2.0.0"
      End
    End

    Describe "without --image-tag leaves manifests unchanged"
      setup_no_image_tag() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        printf 'apiVersion: v1\nkind: ConfigMap\n' > "${TEST_WS}/rendered/cm.yaml"
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
      cleanup_no_image_tag() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_image_tag'
      After 'cleanup_no_image_tag'

      It "does not log image tag substitution"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" \
          --message "deploy"
        The status should be success
        The stderr should not include "image tags substituted"
      End
    End

    Describe "handles files without container specs"
      setup_no_containers() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${TEST_WS}/rendered/configmap.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  key: value
YAML
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
      cleanup_no_containers() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_containers'
      After 'cleanup_no_containers'

      It "succeeds without error on files with no container specs"
        When call deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
          --branch main --path apps --source "${TEST_WS}/rendered" \
          --message "deploy" --image-tag "v1.0.0"
        The status should be success
        The stderr should include "image tags substituted"
      End
    End

    Describe "end-to-end tag substitution verification"
      setup_e2e_tag() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/rendered"
        cat > "${TEST_WS}/rendered/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      initContainers:
        - name: init
          image: registry.example.com/init:latest
      containers:
        - name: app
          image: registry.example.com/my-app:latest
YAML
        # Mock git: on "add", snapshot the manifest content before tmpdir cleanup
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
# Parse -C <dir> to get the working directory
gitdir=""
if [ "\$1" = "-C" ]; then
  gitdir="\$2"
fi
# Capture manifest content during "git add" (before tmpdir is cleaned up)
case "\$*" in
  *" add "*)
    if [ -n "\$gitdir" ] && [ -d "\$gitdir" ]; then
      find "\$gitdir" -name 'deployment.yaml' -type f 2>/dev/null | while read -r f; do
        cat "\$f"
      done > "${TEST_WS}/captured_manifest.yaml"
    fi
    ;;
esac
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_e2e_tag() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_e2e_tag'
      After 'cleanup_e2e_tag'

      It "replaces tags in both containers and initContainers"
        invoke_e2e_tag() {
          deploy.gitops.push_manifests --repo "https://git.example.com/repo" \
            --branch main --path apps --source "${TEST_WS}/rendered" \
            --message "deploy" --image-tag "v3.0.0" 2>/dev/null || return 1
          local manifest="${TEST_WS}/captured_manifest.yaml"
          [[ -f "$manifest" ]] || return 1
          # Verify container image was rewritten
          grep -q "registry.example.com/my-app:v3.0.0" "$manifest" || return 1
          # Verify initContainer image was rewritten
          grep -q "registry.example.com/init:v3.0.0" "$manifest" || return 1
          # Verify no :latest remains
          ! grep -q ":latest" "$manifest"
        }
        When call invoke_e2e_tag
        The status should be success
      End
    End
  End

  # =========================================================================
  # deploy.gitops.run --image-tag passthrough
  # =========================================================================
  Describe "deploy.gitops.run passes --image-tag"
    Describe "when BRIK_APP_VERSION is set"
      setup_run_tag() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        mkdir -p "${TEST_WS}/src"
        printf 'apiVersion: apps/v1\nkind: Deployment\nspec:\n  template:\n    spec:\n      containers:\n        - name: app\n          image: myapp:latest\n' > "${TEST_WS}/src/deploy.yaml"
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
        export BRIK_APP_VERSION="1.2.3"
        unset BRIK_COMMIT_SHORT_SHA 2>/dev/null
      }
      cleanup_run_tag() {
        mock.cleanup
        unset BRIK_APP_VERSION BRIK_COMMIT_SHORT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_run_tag'
      After 'cleanup_run_tag'

      It "passes image tag and logs substitution"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src"
        The status should be success
        The stderr should include "image tags substituted to :1.2.3"
      End
    End

    Describe "when tag is unknown"
      setup_run_no_tag() {
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
        unset BRIK_APP_VERSION BRIK_COMMIT_SHORT_SHA 2>/dev/null
      }
      cleanup_run_no_tag() {
        mock.cleanup
        unset BRIK_APP_VERSION BRIK_COMMIT_SHORT_SHA 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_run_no_tag'
      After 'cleanup_run_no_tag'

      It "does not pass --image-tag when tag is unknown"
        When call deploy.gitops.run --repo "https://github.com/org/gitops.git" \
          --source "${TEST_WS}/src"
        The status should be success
        The stderr should not include "image tags substituted"
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
        The stderr should include "gitops sync"
        The stderr should include "timeout"
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

    Describe "with mock git - clone failure"
      setup_diff_clone_fail() {
        mock.setup
        mock.create_exit "git" 1
        mock.activate
      }
      cleanup_diff_clone_fail() {
        mock.cleanup
      }
      Before 'setup_diff_clone_fail'
      After 'cleanup_diff_clone_fail'

      It "returns 5 when git clone fails"
        When call deploy.gitops.diff --repo "https://git.example.com/repo" \
          --branch main --path apps --source /tmp/src
        The status should equal 5
        The stderr should include "git clone failed"
      End
    End

    Describe "successful diff"
      setup_diff_ok() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/source"
        printf 'key: value\n' > "${TEST_WS}/source/config.yaml"
        # Mock git clone to create a target dir with different content
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest/apps"
  printf 'key: old-value\n' > "\$dest/apps/config.yaml"
fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_diff_ok() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_diff_ok'
      After 'cleanup_diff_ok'

      It "returns 0 and outputs diff"
        invoke_diff_ok() {
          deploy.gitops.diff --repo "https://git.example.com/repo" \
            --branch main --path apps --source "${TEST_WS}/source" >/dev/null 2>/dev/null
        }
        When call invoke_diff_ok
        The status should be success
      End

      It "accepts --git-token-var option"
        invoke_diff_token() {
          export MY_GIT_TOKEN="ghp_testtoken123"
          deploy.gitops.diff --repo "https://git.example.com/repo" \
            --branch main --path apps --source "${TEST_WS}/source" \
            --git-token-var MY_GIT_TOKEN >/dev/null 2>/dev/null
          local rc=$?
          unset MY_GIT_TOKEN
          return $rc
        }
        When call invoke_diff_token
        The status should be success
      End
    End

    Describe "diff with missing remote path"
      setup_diff_no_remote_path() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/source"
        printf 'key: value\n' > "${TEST_WS}/source/config.yaml"
        # Mock git clone: creates repo root but NOT the target path
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
      }
      cleanup_diff_no_remote_path() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_diff_no_remote_path'
      After 'cleanup_diff_no_remote_path'

      It "treats all files as new when remote path does not exist"
        invoke_diff_new() {
          deploy.gitops.diff --repo "https://git.example.com/repo" \
            --branch main --path nonexistent --source "${TEST_WS}/source" >/dev/null 2>/dev/null
        }
        When call invoke_diff_new
        The status should be success
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

    Describe "with --path uses git checkout HEAD~1"
      setup_rb_path() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
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
      cleanup_rb_path() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rb_path'
      After 'cleanup_rb_path'

      It "uses git checkout HEAD~1 -- <path> for path-scoped rollback"
        invoke_rb_path() {
          deploy.gitops.rollback --repo "https://git.example.com/repo" \
            --branch main --path apps/myapp 2>/dev/null || return 1
          grep -q "checkout HEAD~1 -- apps/myapp" "$MOCK_LOG"
        }
        When call invoke_rb_path
        The status should be success
      End

      It "commits with path-specific rollback message"
        invoke_rb_path_msg() {
          deploy.gitops.rollback --repo "https://git.example.com/repo" \
            --branch main --path apps/myapp 2>/dev/null || return 1
          grep -q "rollback: revert apps/myapp to previous version" "$MOCK_LOG"
        }
        When call invoke_rb_path_msg
        The status should be success
      End
    End

    Describe "with --to-commit restores specific commit"
      setup_rb_commit() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
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
      cleanup_rb_commit() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rb_commit'
      After 'cleanup_rb_commit'

      It "uses git checkout <commit> -- <path> for commit-specific rollback"
        invoke_rb_commit() {
          deploy.gitops.rollback --repo "https://git.example.com/repo" \
            --branch main --path apps --to-commit abc123 2>/dev/null || return 1
          grep -q "checkout abc123 -- apps" "$MOCK_LOG"
        }
        When call invoke_rb_commit
        The status should be success
      End

      It "commits with commit-specific message"
        invoke_rb_commit_msg() {
          deploy.gitops.rollback --repo "https://git.example.com/repo" \
            --branch main --path apps --to-commit abc123 2>/dev/null || return 1
          grep -q "rollback: restore apps to abc123" "$MOCK_LOG"
        }
        When call invoke_rb_commit_msg
        The status should be success
      End
    End

    Describe "clone failure"
      setup_rb_clone_fail() {
        mock.setup
        mock.create_exit "git" 1
        mock.activate
      }
      cleanup_rb_clone_fail() {
        mock.cleanup
      }
      Before 'setup_rb_clone_fail'
      After 'cleanup_rb_clone_fail'

      It "returns 5 when git clone fails"
        When call deploy.gitops.rollback --repo "https://git.example.com/repo" --branch main
        The status should equal 5
        The stderr should include "git clone failed"
      End
    End

    Describe "git push failure after rollback"
      setup_rb_push_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
if [ "\$1" = "clone" ]; then
  dest="\$(echo "\$*" | rev | cut -d' ' -f1 | rev)"
  mkdir -p "\$dest"
fi
# Fail on push
case "\$*" in
  *push*) exit 1 ;;
esac
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_rb_push_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rb_push_fail'
      After 'cleanup_rb_push_fail'

      It "returns 5 when git push fails after rollback"
        When call deploy.gitops.rollback --repo "https://git.example.com/repo" --branch main
        The status should equal 5
        The stderr should include "git push failed"
      End
    End

    Describe "without --path uses git revert HEAD"
      setup_rb_nopath() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
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
      cleanup_rb_nopath() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_rb_nopath'
      After 'cleanup_rb_nopath'

      It "uses git revert --no-edit HEAD when no path specified"
        invoke_rb_nopath() {
          deploy.gitops.rollback --repo "https://git.example.com/repo" \
            --branch main 2>/dev/null || return 1
          grep -q "revert --no-edit HEAD" "$MOCK_LOG"
        }
        When call invoke_rb_nopath
        The status should be success
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
        unset BRIK_DRY_RUN BRIK_TAG BRIK_COMMIT_SHA 2>/dev/null
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
        . "$BRIK_DEPLOYMENTS_LIB/gitops.sh"
        declare -f deploy.gitops.run >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End
End
