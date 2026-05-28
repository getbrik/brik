Describe "env.sh (transverse variable indirection + env-file sourcing)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"

  # -------------------------------------------------------------------------
  # transverse.env.resolve_indirect
  # -------------------------------------------------------------------------
  Describe "transverse.env.resolve_indirect"
    It "returns the value of a variable referenced by name"
      export BRIK_SPEC_RESOLVE_PROBE="hello-world"
      When call transverse.env.resolve_indirect "BRIK_SPEC_RESOLVE_PROBE"
      The status should be success
      The output should equal "hello-world"
      unset BRIK_SPEC_RESOLVE_PROBE
    End

    It "returns empty string when the referenced variable is unset"
      unset BRIK_SPEC_RESOLVE_MISSING
      When call transverse.env.resolve_indirect "BRIK_SPEC_RESOLVE_MISSING"
      The status should be success
      The output should equal ""
    End

    It "returns empty string when the referenced variable is an empty string"
      export BRIK_SPEC_RESOLVE_EMPTY=""
      When call transverse.env.resolve_indirect "BRIK_SPEC_RESOLVE_EMPTY"
      The status should be success
      The output should equal ""
      unset BRIK_SPEC_RESOLVE_EMPTY
    End

    It "returns empty string and success when var name is empty"
      When call transverse.env.resolve_indirect ""
      The status should be success
      The output should equal ""
    End

    It "preserves values containing whitespace and special characters"
      export BRIK_SPEC_RESOLVE_SPECIAL='line one  tabs	here / == ++'
      When call transverse.env.resolve_indirect "BRIK_SPEC_RESOLVE_SPECIAL"
      The status should be success
      The output should equal 'line one  tabs	here / == ++'
      unset BRIK_SPEC_RESOLVE_SPECIAL
    End
  End

  # -------------------------------------------------------------------------
  # transverse.env.load_project
  # -------------------------------------------------------------------------
  Describe "transverse.env.load_project"
    setup_tempdir() {
      TEMP_ENV_DIR="$(mktemp -d)"
      ORIG_PWD="$PWD"
      cd "$TEMP_ENV_DIR" || return 1
      unset BRIK_CONFIG_FILE
      unset BRIK_SPEC_ENV_FOO BRIK_SPEC_ENV_BAR BRIK_SPEC_ENV_BAZ BRIK_SPEC_ENV_PREEXISTING
    }
    cleanup_tempdir() {
      cd "$ORIG_PWD" || true
      rm -rf "$TEMP_ENV_DIR"
      unset BRIK_CONFIG_FILE
      unset BRIK_SPEC_ENV_FOO BRIK_SPEC_ENV_BAR BRIK_SPEC_ENV_BAZ BRIK_SPEC_ENV_PREEXISTING
    }
    Before 'setup_tempdir'
    After 'cleanup_tempdir'

    It "is a no-op when no brik.yml and no brik.env exist"
      load_and_check() {
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_ENV_FOO:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "UNSET"
    End

    It "auto-detects brik.env at cwd when no brik.yml is declared"
      load_and_check() {
        printf 'BRIK_SPEC_ENV_FOO=from-brik-env\n' > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_ENV_FOO:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "from-brik-env"
    End

    It "auto-detects brik.env when brik.yml does not declare project.env"
      load_and_check() {
        printf 'version: 1\nproject:\n  name: t\n  stack: node\n' > brik.yml
        printf 'BRIK_SPEC_ENV_FOO=auto\n' > brik.env
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_ENV_FOO:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "auto"
    End

    It "sources the path declared in brik.yml .project.env"
      load_and_check() {
        mkdir -p envs
        printf 'BRIK_SPEC_ENV_FOO=from-declared\n' > envs/project.env
        printf 'version: 1\nproject:\n  name: t\n  stack: node\n  env: envs/project.env\n' > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_ENV_FOO:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "from-declared"
    End

    It "returns 1 when declared project.env path is missing on disk"
      load_and_check() {
        printf 'version: 1\nproject:\n  name: t\n  stack: node\n  env: envs/missing.env\n' > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_ENV_FOO:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "1"
      The line 2 of output should equal "UNSET"
      The stderr should include "missing"
    End

    It "does not overwrite already-exported variables (CI precedence)"
      load_and_check() {
        export BRIK_SPEC_ENV_PREEXISTING="from-ci"
        printf 'BRIK_SPEC_ENV_PREEXISTING=from-file\n' > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_ENV_PREEXISTING"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "from-ci"
    End

    It "exports new variables to the caller"
      load_and_check() {
        printf 'BRIK_SPEC_ENV_FOO=one\nBRIK_SPEC_ENV_BAR=two\n' > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s\n%s' "$rc" "$BRIK_SPEC_ENV_FOO" "$BRIK_SPEC_ENV_BAR"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "one"
      The line 3 of output should equal "two"
    End

    It "skips comment lines and blank lines"
      load_and_check() {
        {
          printf '# this is a comment\n'
          printf '\n'
          printf '   # indented comment\n'
          printf 'BRIK_SPEC_ENV_FOO=kept\n'
        } > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_ENV_FOO"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "kept"
    End

    It "strips matched surrounding quotes from values"
      load_and_check() {
        {
          printf 'BRIK_SPEC_ENV_FOO="double quoted"\n'
          printf "BRIK_SPEC_ENV_BAR='single quoted'\n"
          printf 'BRIK_SPEC_ENV_BAZ=unquoted value\n'
        } > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s\n%s\n%s' "$rc" "$BRIK_SPEC_ENV_FOO" "$BRIK_SPEC_ENV_BAR" "$BRIK_SPEC_ENV_BAZ"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "double quoted"
      The line 3 of output should equal "single quoted"
      The line 4 of output should equal "unquoted value"
    End

    It "strips CRLF line endings from Windows-authored env files"
      load_and_check() {
        printf 'BRIK_SPEC_ENV_FOO=value-no-cr\r\nBRIK_SPEC_ENV_BAR=value-two\r\n' > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n[%s]\n[%s]' "$rc" "$BRIK_SPEC_ENV_FOO" "$BRIK_SPEC_ENV_BAR"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "[value-no-cr]"
      The line 3 of output should equal "[value-two]"
    End

    It "ignores malformed lines without KEY=VALUE shape"
      load_and_check() {
        {
          printf 'not-a-valid-line\n'
          printf '123INVALID=nope\n'
          printf 'BRIK_SPEC_ENV_FOO=ok\n'
        } > brik.env
        transverse.env.load_project
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_ENV_FOO"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "ok"
    End
  End

  # -------------------------------------------------------------------------
  # transverse.env.load_deploy_env
  # -------------------------------------------------------------------------
  Describe "transverse.env.load_deploy_env"
    setup_deploy_dir() {
      TEMP_DEPLOY_DIR="$(mktemp -d)"
      ORIG_PWD="$PWD"
      cd "$TEMP_DEPLOY_DIR" || return 1
      unset BRIK_CONFIG_FILE
      unset BRIK_SPEC_DEPLOY_API_URL BRIK_SPEC_DEPLOY_FLAG
    }
    cleanup_deploy_dir() {
      cd "$ORIG_PWD" || true
      rm -rf "$TEMP_DEPLOY_DIR"
      unset BRIK_CONFIG_FILE
      unset BRIK_SPEC_DEPLOY_API_URL BRIK_SPEC_DEPLOY_FLAG
    }
    Before 'setup_deploy_dir'
    After 'cleanup_deploy_dir'

    It "is a no-op when env name is empty"
      load_and_check() {
        transverse.env.load_deploy_env ""
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_DEPLOY_API_URL:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "UNSET"
    End

    It "is a no-op when no brik.yml is loaded"
      load_and_check() {
        transverse.env.load_deploy_env "staging"
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_DEPLOY_API_URL:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "UNSET"
    End

    It "is a no-op when env_file is not declared for the given env"
      load_and_check() {
        printf 'version: 1\ndeploy:\n  environments:\n    staging: {}\n' > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_deploy_env "staging"
        local rc=$?
        printf '%s\n%s' "$rc" "${BRIK_SPEC_DEPLOY_API_URL:-UNSET}"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "UNSET"
    End

    It "sources file declared at deploy.environments.<env>.env_file"
      load_and_check() {
        mkdir -p envs
        printf 'BRIK_SPEC_DEPLOY_API_URL=https://staging.example.com\n' > envs/staging.env
        {
          printf 'version: 1\n'
          printf 'deploy:\n'
          printf '  environments:\n'
          printf '    staging:\n'
          printf '      env_file: envs/staging.env\n'
        } > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_deploy_env "staging"
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_DEPLOY_API_URL"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "https://staging.example.com"
    End

    It "returns 1 when env_file is declared but missing on disk"
      load_and_check() {
        {
          printf 'version: 1\n'
          printf 'deploy:\n'
          printf '  environments:\n'
          printf '    staging:\n'
          printf '      env_file: envs/missing.env\n'
        } > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_deploy_env "staging"
        local rc=$?
        printf '%s' "$rc"
      }
      When call load_and_check
      The status should be success
      The output should equal "1"
      The stderr should include "env_file"
    End

    It "loads only the declared env and ignores siblings"
      load_and_check() {
        mkdir -p envs
        printf 'BRIK_SPEC_DEPLOY_FLAG=prod\n' > envs/production.env
        printf 'BRIK_SPEC_DEPLOY_FLAG=staging\n' > envs/staging.env
        {
          printf 'version: 1\n'
          printf 'deploy:\n'
          printf '  environments:\n'
          printf '    staging:\n'
          printf '      env_file: envs/staging.env\n'
          printf '    production:\n'
          printf '      env_file: envs/production.env\n'
        } > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        transverse.env.load_deploy_env "production"
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_DEPLOY_FLAG"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "prod"
    End

    It "does not overwrite already-exported deploy variables"
      load_and_check() {
        mkdir -p envs
        printf 'BRIK_SPEC_DEPLOY_FLAG=from-file\n' > envs/staging.env
        {
          printf 'version: 1\n'
          printf 'deploy:\n'
          printf '  environments:\n'
          printf '    staging:\n'
          printf '      env_file: envs/staging.env\n'
        } > brik.yml
        export BRIK_CONFIG_FILE="$PWD/brik.yml"
        export BRIK_SPEC_DEPLOY_FLAG="from-ci"
        transverse.env.load_deploy_env "staging"
        local rc=$?
        printf '%s\n%s' "$rc" "$BRIK_SPEC_DEPLOY_FLAG"
      }
      When call load_and_check
      The status should be success
      The line 1 of output should equal "0"
      The line 2 of output should equal "from-ci"
    End
  End
End
