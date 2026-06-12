Describe "transverse/state_repo.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/git.sh"
  Include "$BRIK_TRANSVERSE_LIB/state_repo.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # =========================================================================
  # _transverse.state_repo._safe_url
  # =========================================================================
  Describe "_transverse.state_repo._safe_url"
    It "masks credentials in URL"
      When call _transverse.state_repo._safe_url "https://token123@github.com/org/repo.git"
      The output should equal "https://***@github.com/org/repo.git"
    End

    It "returns URL unchanged when no credentials"
      When call _transverse.state_repo._safe_url "https://github.com/org/repo.git"
      The output should equal "https://github.com/org/repo.git"
    End
  End

  # =========================================================================
  # _transverse.state_repo._inject_token
  # =========================================================================
  Describe "_transverse.state_repo._inject_token"
    It "returns URL unchanged when token_var is empty"
      When call _transverse.state_repo._inject_token "https://github.com/org/repo.git" ""
      The output should equal "https://github.com/org/repo.git"
    End

    It "injects token into URL"
      inject_token_test() {
        export MY_GIT_TOKEN="secret123"
        _transverse.state_repo._inject_token "https://github.com/org/repo.git" "MY_GIT_TOKEN"
        local rc=$?
        unset MY_GIT_TOKEN
        return $rc
      }
      When call inject_token_test
      The output should equal "https://secret123@github.com/org/repo.git"
    End

    It "returns 4 when the token variable is empty"
      unset EMPTY_TOKEN_VAR 2>/dev/null
      When call _transverse.state_repo._inject_token "https://github.com/org/repo.git" "EMPTY_TOKEN_VAR"
      The status should equal 4
      The stderr should include "token variable is empty"
    End

    It "injects the token into a plain-http URL (declared lab posture)"
      inject_token_http() {
        export MY_GIT_TOKEN="secret123"
        _transverse.state_repo._inject_token "http://gitea.lab:3000/org/repo.git" "MY_GIT_TOKEN"
        local rc=$?
        unset MY_GIT_TOKEN
        return $rc
      }
      When call inject_token_http
      The output should equal "http://secret123@gitea.lab:3000/org/repo.git"
    End
  End

  # =========================================================================
  # _transverse.state_repo._ca_for_url
  # =========================================================================
  Describe "_transverse.state_repo._ca_for_url"
    setup_githost_ca() {
      CA_INFRA="$(mktemp -d)"
      mkdir -p "$CA_INFRA/endpoints" "$CA_INFRA/trust/ca/gitea.lab"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$CA_INFRA/referential.yml"
      cat > "$CA_INFRA/endpoints/git.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git
product: gitea
api_url: https://gitea.lab:3443/api/v1
git_url: https://gitea.lab:3443
tls:
  trust: custom-ca
YAML
      printf 'PEM\n' > "$CA_INFRA/trust/ca/gitea.lab/ca.crt"
      export BRIK_INFRA_DIR="$CA_INFRA"
    }
    cleanup_githost_ca() { rm -rf "$CA_INFRA"; unset BRIK_INFRA_DIR CA_INFRA; }
    Before 'setup_githost_ca'
    After 'cleanup_githost_ca'

    It "resolves the bundle for a repo URL on the declared GitHost (userinfo and port ignored)"
      When call _transverse.state_repo._ca_for_url "https://token@gitea.lab:3443/brik/state.git"
      The status should be success
      The output should equal "$CA_INFRA/trust/ca/gitea.lab/ca.crt"
    End

    It "is empty for a repo URL on another host"
      When call _transverse.state_repo._ca_for_url "https://github.com/org/repo.git"
      The status should be success
      The output should equal ""
    End

    It "fails closed when the GitHost declares custom-ca without its bundle"
      ca_missing() {
        rm "$CA_INFRA/trust/ca/gitea.lab/ca.crt"
        _transverse.state_repo._ca_for_url "https://gitea.lab:3443/brik/state.git"
      }
      When call ca_missing
      The status should equal 7
      The stderr should include "trust/ca/gitea.lab"
    End
  End

  # =========================================================================
  # transverse.state_repo.clone
  # =========================================================================
  Describe "transverse.state_repo.clone"
    It "returns 2 when repo is missing"
      When call transverse.state_repo.clone "" /tmp/dest
      The status should equal 2
      The stderr should include "repo is required"
    End

    It "returns 2 when dest is missing"
      When call transverse.state_repo.clone "https://git.example.com/repo" ""
      The status should equal 2
      The stderr should include "dest is required"
    End

    It "returns 2 for unknown option"
      When call transverse.state_repo.clone "https://git.example.com/repo" /tmp/dest --badopt foo
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
        When call transverse.state_repo.clone "https://git.example.com/repo" /tmp/dest --branch main
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock git"
      setup_git() {
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
      cleanup_git() {
        mock.cleanup
        unset BRIK_DRY_RUN MY_GIT_TOKEN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_git'
      After 'cleanup_git'

      It "clones shallow with --depth 1 --branch"
        invoke_clone() {
          transverse.state_repo.clone "https://git.example.com/repo" "${TEST_WS}/clone" \
            --branch main 2>/dev/null || return 1
          grep -q "clone --depth 1 --branch main" "$MOCK_LOG"
        }
        When call invoke_clone
        The status should be success
      End

      It "honours a custom --depth"
        invoke_depth() {
          transverse.state_repo.clone "https://git.example.com/repo" "${TEST_WS}/clone" \
            --branch main --depth 10 2>/dev/null || return 1
          grep -q "clone --depth 10 --branch main" "$MOCK_LOG"
        }
        When call invoke_depth
        The status should be success
      End

      It "injects an indirect token into the clone URL"
        invoke_token() {
          export MY_GIT_TOKEN="secret-token-123"
          transverse.state_repo.clone "https://github.com/org/state.git" "${TEST_WS}/clone" \
            --branch main --token-var MY_GIT_TOKEN 2>/dev/null || return 1
          grep -q "secret-token-123" "$MOCK_LOG"
        }
        When call invoke_token
        The status should be success
      End

      It "masks the token in log output"
        export MY_GIT_TOKEN="secret-token-123"
        When call transverse.state_repo.clone "https://github.com/org/state.git" "${TEST_WS}/clone" \
          --branch main --token-var MY_GIT_TOKEN
        The status should be success
        The stderr should include "***"
        The stderr should not include "secret-token-123"
      End

      It "dry-run mode does not clone"
        invoke_dryrun() {
          transverse.state_repo.clone "https://git.example.com/repo" "${TEST_WS}/clone" \
            --branch main --dry-run 2>/dev/null
          ! grep -q "clone" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_dryrun
        The status should be success
      End
    End

    Describe "clone failure"
      setup_clone_fail() {
        mock.setup
        mock.create_exit "git" 1
        mock.activate
      }
      cleanup_clone_fail() {
        mock.cleanup
      }
      Before 'setup_clone_fail'
      After 'cleanup_clone_fail'

      It "returns 5 when git clone fails"
        When call transverse.state_repo.clone "https://git.example.com/repo" /tmp/dest --branch main
        The status should equal 5
        The stderr should include "git clone failed"
      End
    End
  End

  # =========================================================================
  # transverse.state_repo.append
  # =========================================================================
  Describe "transverse.state_repo.append"
    setup_append() {
      TEST_WS="$(mktemp -d)"
    }
    cleanup_append() {
      rm -rf "$TEST_WS"
    }
    Before 'setup_append'
    After 'cleanup_append'

    It "returns 2 when repo_dir is missing"
      When call transverse.state_repo.append "" "evidence/x.json"
      The status should equal 2
      The stderr should include "repo_dir is required"
    End

    It "returns 2 when relpath is missing"
      When call transverse.state_repo.append "$TEST_WS" ""
      The status should equal 2
      The stderr should include "relpath is required"
    End

    It "returns 6 when repo_dir does not exist"
      When call transverse.state_repo.append "/nonexistent-dir-xyz" "evidence/x.json"
      The status should equal 6
      The stderr should include "state-repo dir not found"
    End

    It "rejects an absolute event path"
      When call transverse.state_repo.append "$TEST_WS" "/etc/passwd"
      The status should equal 2
      The stderr should include "invalid event path"
    End

    It "rejects a path-traversal event path"
      When call transverse.state_repo.append "$TEST_WS" "../escape.json"
      The status should equal 2
      The stderr should include "invalid event path"
    End

    It "writes an event file from stdin, creating parent dirs"
      write_event() {
        printf '{"k":"v"}' | transverse.state_repo.append "$TEST_WS" "evidence/1.2.3/event.json" || return 1
        [[ -f "${TEST_WS}/evidence/1.2.3/event.json" ]] || return 1
        grep -q '"k":"v"' "${TEST_WS}/evidence/1.2.3/event.json"
      }
      When call write_event
      The status should be success
    End

    It "refuses to overwrite an existing event (append-only)"
      overwrite_event() {
        mkdir -p "${TEST_WS}/evidence"
        printf 'first' > "${TEST_WS}/evidence/e.json"
        printf 'second' | transverse.state_repo.append "$TEST_WS" "evidence/e.json"
      }
      When call overwrite_event
      The status should equal 6
      The stderr should include "append-only violation"
    End
  End

  # =========================================================================
  # transverse.state_repo.commit
  # =========================================================================
  Describe "transverse.state_repo.commit"
    It "returns 2 when repo_dir is missing"
      When call transverse.state_repo.commit "" "msg"
      The status should equal 2
      The stderr should include "repo_dir is required"
    End

    It "returns 2 when message is missing"
      When call transverse.state_repo.commit "/tmp/dir" ""
      The status should equal 2
      The stderr should include "message is required"
    End

    It "returns 2 for unknown option"
      When call transverse.state_repo.commit "/tmp/dir" "msg" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "against a real git repo"
      setup_repo() {
        TEST_WS="$(mktemp -d)"
        git -C "$TEST_WS" init -q
        git -C "$TEST_WS" config user.email "seed@noreply"
        git -C "$TEST_WS" config user.name "Seed"
        printf 'base' > "${TEST_WS}/base.txt"
        git -C "$TEST_WS" add -A
        git -C "$TEST_WS" commit -q -m "base"
      }
      cleanup_repo() {
        rm -rf "$TEST_WS"
      }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "commits staged changes"
        do_commit() {
          printf 'new' > "${TEST_WS}/new.txt"
          transverse.state_repo.commit "$TEST_WS" "feat: add new" 2>/dev/null || return 1
          git -C "$TEST_WS" log -1 --pretty=%s | grep -q "feat: add new"
        }
        When call do_commit
        The status should be success
      End

      It "applies the default brik-ci identity"
        do_identity() {
          printf 'id' > "${TEST_WS}/id.txt"
          transverse.state_repo.commit "$TEST_WS" "chore: id" 2>/dev/null || return 1
          git -C "$TEST_WS" log -1 --pretty=%ae | grep -q "brik-ci@noreply"
        }
        When call do_identity
        The status should be success
      End

      It "is idempotent: returns 0 with no changes"
        When call transverse.state_repo.commit "$TEST_WS" "noop"
        The status should be success
        The stderr should include "no changes to commit"
      End

      It "returns 5 with --fail-if-empty and no changes"
        When call transverse.state_repo.commit "$TEST_WS" "noop" --fail-if-empty
        The status should equal 5
        The stderr should include "no changes"
      End
    End
  End

  # =========================================================================
  # transverse.state_repo.push
  # =========================================================================
  Describe "transverse.state_repo.push"
    It "returns 2 when repo_dir is missing"
      When call transverse.state_repo.push ""
      The status should equal 2
      The stderr should include "repo_dir is required"
    End

    It "returns 2 for unknown option"
      When call transverse.state_repo.push "/tmp/dir" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with mock git"
      setup_push() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_git.log"
        cat > "${MOCK_BIN}/git" <<SCRIPT
#!/bin/sh
printf 'git %s\n' "\$*" >> "${MOCK_LOG}"
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_push() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_push'
      After 'cleanup_push'

      It "pushes the repo dir"
        invoke_push() {
          transverse.state_repo.push "$TEST_WS" 2>/dev/null || return 1
          grep -q "push" "$MOCK_LOG"
        }
        When call invoke_push
        The status should be success
      End

      It "dry-run mode does not push"
        invoke_push_dryrun() {
          transverse.state_repo.push "$TEST_WS" --dry-run 2>/dev/null
          ! grep -q "push" "$MOCK_LOG" 2>/dev/null
        }
        When call invoke_push_dryrun
        The status should be success
      End
    End

    Describe "push failure with credential redaction"
      setup_push_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        cat > "${MOCK_BIN}/git" <<'SCRIPT'
#!/bin/sh
echo "fatal: https://token:secret@host/repo.git rejected" >&2
exit 1
SCRIPT
        chmod +x "${MOCK_BIN}/git"
        mock.activate
      }
      cleanup_push_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_push_fail'
      After 'cleanup_push_fail'

      It "returns 5 and masks credentials in the error"
        When call transverse.state_repo.push "$TEST_WS"
        The status should equal 5
        The stderr should include "git push failed"
        The stderr should include "***"
        The stderr should not include "secret@host"
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
        . "$BRIK_TRANSVERSE_LIB/state_repo.sh"
        declare -f transverse.state_repo.clone >/dev/null && echo "ok" || echo "missing"
      }
      When call double_include
      The output should equal "ok"
    End
  End

  # =========================================================================
  # ssh-signed evidence commits (evidence-commit-signing provider)
  # =========================================================================
  Describe "commit --sign and verify_head (ssh-signing)"
    Include "$BRIK_TRANSVERSE_LIB/config.sh"
    Include "$BRIK_TRANSVERSE_LIB/infra.sh"

    setup_signing() {
      SIGN_DIR="$(mktemp -d)"

      REPO_DIR="$SIGN_DIR/repo"
      mkdir -p "$REPO_DIR"
      git -C "$REPO_DIR" init -q -b main
      printf '{}\n' > "$REPO_DIR/event.json"

      ssh-keygen -t ed25519 -N "" -q -f "$SIGN_DIR/id_ed25519"

      INFRA_DIR="$SIGN_DIR/infra"
      mkdir -p "$INFRA_DIR/credentials" "$INFRA_DIR/trust"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$INFRA_DIR/referential.yml"
      cat > "$INFRA_DIR/credentials/evidence-signing.yml" <<YAML
apiVersion: brik.dev/referential/v1
kind: Credential
name: evidence-signing
method: ssh-key
private_key: file://$SIGN_DIR/id_ed25519
YAML
      # Principals are verified in the 'git' namespace (commits AND tags);
      # a 'git-commit' namespace entry fails with "key is not permitted".
      printf 'brik-ci@noreply namespaces="git" %s\n' "$(cat "$SIGN_DIR/id_ed25519.pub")" \
        > "$INFRA_DIR/trust/allowed_signers"

      export BRIK_INFRA_DIR="$INFRA_DIR"
    }
    cleanup_signing() {
      rm -rf "$SIGN_DIR"
      unset BRIK_INFRA_DIR SIGN_DIR REPO_DIR INFRA_DIR
    }
    Before 'setup_signing'
    After 'cleanup_signing'

    It "signs with the referential's key and verify_head accepts the signature"
      sign_roundtrip() {
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign || return $?
        transverse.state_repo.verify_head "$REPO_DIR"
      }
      When call sign_roundtrip
      The status should be success
      The stderr should include 'Good "git" signature'
    End

    It "materializes an env:// key into a transient file and signs with it"
      sign_env_key() {
        SIGN_SPEC_KEY="$(cat "$SIGN_DIR/id_ed25519")"
        export SIGN_SPEC_KEY
        yq -i '.private_key = "env://SIGN_SPEC_KEY"' "$INFRA_DIR/credentials/evidence-signing.yml"
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign || return $?
        transverse.state_repo.verify_head "$REPO_DIR"
      }
      When call sign_env_key
      The status should be success
      The stderr should include 'Good "git" signature'
    End

    It "fails closed (7) on --sign without an evidence-signing credential"
      sign_no_cred() {
        rm "$INFRA_DIR/credentials/evidence-signing.yml"
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign
      }
      When call sign_no_cred
      The status should equal 7
      The stderr should include "evidence-signing"
    End

    It "fails closed (7) when the evidence-signing credential is not an ssh-key"
      sign_wrong_method() {
        cat > "$INFRA_DIR/credentials/evidence-signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: evidence-signing
method: token
token: env://SOME_TOKEN
YAML
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign
      }
      When call sign_wrong_method
      The status should equal 7
      The stderr should include "ssh-key"
    End

    It "verify_head rejects (5) a signer absent from allowed_signers"
      verify_unknown_signer() {
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign || return $?
        : > "$INFRA_DIR/trust/allowed_signers"
        transverse.state_repo.verify_head "$REPO_DIR" 2>/dev/null
      }
      When call verify_unknown_signer
      The status should equal 5
    End

    It "verify_head rejects (5) an unsigned HEAD"
      verify_unsigned() {
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" || return $?
        transverse.state_repo.verify_head "$REPO_DIR" 2>/dev/null
      }
      When call verify_unsigned
      The status should equal 5
    End

    It "verify_head fails closed (7) when the referential has no allowed_signers"
      verify_no_trust() {
        transverse.state_repo.commit "$REPO_DIR" "evidence: spec" --sign || return $?
        rm "$INFRA_DIR/trust/allowed_signers"
        transverse.state_repo.verify_head "$REPO_DIR"
      }
      When call verify_no_trust
      The status should equal 7
      The stderr should include "allowed_signers"
    End
  End

  # =========================================================================
  # branch-protection check against the GitHost API (CD init)
  # =========================================================================
  Describe "transverse.state_repo.check_protection"
    Include "$BRIK_TRANSVERSE_LIB/config.sh"
    Include "$BRIK_TRANSVERSE_LIB/infra.sh"

    setup_protection() {
      PROT_DIR="$(mktemp -d)"
      INFRA_DIR="$PROT_DIR/infra"
      MOCK_BIN_DIR="$PROT_DIR/bin"
      mkdir -p "$INFRA_DIR/endpoints" "$INFRA_DIR/credentials" "$INFRA_DIR/bindings" "$MOCK_BIN_DIR"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$INFRA_DIR/referential.yml"
      write_githost gitea
      cat > "$INFRA_DIR/credentials/git-api.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: git-api
method: token
token: env://PROT_SPEC_TOKEN
YAML
      cat > "$INFRA_DIR/bindings/prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: prod
endpoints:
  git-host: git-api
YAML
      export BRIK_INFRA_DIR="$INFRA_DIR" PROT_SPEC_TOKEN="t0ken"
    }
    cleanup_protection() {
      rm -rf "$PROT_DIR"
      unset BRIK_INFRA_DIR PROT_SPEC_TOKEN PROT_DIR INFRA_DIR MOCK_BIN_DIR
    }
    Before 'setup_protection'
    After 'cleanup_protection'

    write_githost() {
      cat > "$INFRA_DIR/endpoints/git-host.yml" <<YAML
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git-host
product: $1
api_url: http://git.lab:3000
tls:
  trust: insecure
YAML
    }

    # A curl mock that honours -o (writes the canned body there) and prints
    # the canned HTTP code, the way the implementation invokes curl.
    mock_api() {
      local body="$1" code="$2"
      cat > "$MOCK_BIN_DIR/curl" <<EOF
#!/bin/sh
out=""
prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  prev="\$a"
done
[ -n "\$out" ] && printf '%s' '$body' > "\$out"
printf '%s' '$code'
EOF
      chmod +x "$MOCK_BIN_DIR/curl"
    }

    check() {
      PATH="$MOCK_BIN_DIR:$PATH" transverse.state_repo.check_protection \
        "http://git.lab:3000/brik/config-deploy.git" main --environment prod
    }

    It "confirms a protected branch on gitea"
      gitea_protected() { mock_api '[{"branch_name":"main"}]' 200; check; }
      When call gitea_protected
      The status should be success
      The stderr should include "protected"
    End

    It "reports (10) an unprotected branch on gitea"
      gitea_unprotected() { mock_api '[]' 200; check 2>/dev/null; }
      When call gitea_unprotected
      The status should equal 10
    End

    It "confirms a protected branch on gitlab"
      gitlab_protected() { write_githost gitlab; mock_api '[{"name":"main"}]' 200; check; }
      When call gitlab_protected
      The status should be success
      The stderr should include "protected"
    End

    It "confirms a protected branch on github (200 on the protection endpoint)"
      github_protected() { write_githost github; mock_api '{}' 200; check; }
      When call github_protected
      The status should be success
      The stderr should include "protected"
    End

    It "reports (10) an unprotected branch on github (404)"
      github_unprotected() { write_githost github; mock_api '{"message":"Branch not protected"}' 404; check 2>/dev/null; }
      When call github_unprotected
      The status should equal 10
    End

    It "fails (5) when the GitHost API errors"
      api_error() { mock_api '' 500; check 2>/dev/null; }
      When call api_error
      The status should equal 5
    End

    It "fails closed (7) when no GitHost endpoint is declared"
      no_githost() { rm "$INFRA_DIR/endpoints/git-host.yml"; check 2>/dev/null; }
      When call no_githost
      The status should equal 7
    End

    It "fails closed (7) when the environment binds no credential for the git host"
      unbound() { rm "$INFRA_DIR/bindings/prod.yml"; check 2>/dev/null; }
      When call unbound
      The status should equal 7
    End
  End
End
