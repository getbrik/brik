Describe "cli/infra.sh - cli.infra.run internals (in-process)"
  # In-process Includes so kcov traces every line. Subprocess calls via
  # "$BRIK_BIN" are NOT traced; that is what infra_cli_spec.sh exercises.
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/infra.sh"

  # A fresh, isolated target dir per example so the scaffold heredocs run
  # against an empty tree and never collide with the repo.
  setup_dir() {
    TARGET_DIR="$(mktemp -d)/instance"
    # Validation needs a JSON Schema validator; some examples skip on absence.
    validator_missing() {
      ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1
    }
  }
  cleanup_dir() {
    rm -rf "${TARGET_DIR%/instance}"
    unset TARGET_DIR BRIK_INFRA_DIR BRIK_INFRA_REPO
  }
  Before 'setup_dir'
  After 'cleanup_dir'

  Describe "cli.infra.run dispatcher"
    It "prints help for -h"
      When call cli.infra.run -h
      The status should eq 0
      The output should include "brik"
    End

    It "rejects (2) a missing subcommand"
      When call cli.infra.run
      The status should eq 2
      The stderr should include "requires a subcommand"
    End

    It "rejects (2) an unknown subcommand"
      When call cli.infra.run frobnicate
      The status should eq 2
      The stderr should include "frobnicate"
    End

    It "routes 'init' to the scaffolder"
      When call cli.infra.run init --profile p-local --dir "$TARGET_DIR"
      The status should eq 0
      The output should include "Created a p-local"
      The path "$TARGET_DIR/referential.yml" should be file
    End

    It "routes 'validate' to the validator"
      Skip if "no JSON Schema validator on PATH" validator_missing
      route_validate() {
        cli.infra.run init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        cli.infra.run validate --dir "$TARGET_DIR"
      }
      When call route_validate
      The status should eq 0
      The output should include "valid"
    End

    It "routes 'secrets' to the secrets lister"
      route_secrets() {
        cli.infra.run init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        cli.infra.run secrets --dir "$TARGET_DIR"
      }
      When call route_secrets
      The status should eq 0
      The output should include "Pipeline-side secrets"
    End
  End

  Describe "_cli.infra._init - scaffolds each profile in-process"
    Parameters
      p-open      registry-push      "env://BRIK_REGISTRY_TOKEN"
      p-entreprise registry-push     "bao://secret/ci/registry#password"
      p-lab       registry-push      "env://BRIK_REGISTRY_USER"
      p-local     referential        "profile: p-local"
    End

    It "init --profile $1 writes the referential and runs the heredoc"
      When call _cli.infra._init --profile "$1" --dir "$TARGET_DIR"
      The status should eq 0
      The output should include "Created a $1 referential instance"
      The output should include "BRIK_INFRA_DIR"
      The path "$TARGET_DIR/referential.yml" should be file
    End
  End

  Describe "_cli.infra._init - non-local profiles emit endpoints/credentials/bindings"
    Parameters
      p-open
      p-entreprise
      p-lab
    End

    It "init --profile $1 scaffolds the full endpoint set"
      scaffold() {
        _cli.infra._init --profile "$1" --dir "$TARGET_DIR" >/dev/null || return $?
        [[ -f "$TARGET_DIR/endpoints/registry-candidate.yml" \
           && -f "$TARGET_DIR/endpoints/registry-release.yml" \
           && -f "$TARGET_DIR/endpoints/git-host.yml" \
           && -f "$TARGET_DIR/endpoints/signing.yml" \
           && -f "$TARGET_DIR/credentials/git-api.yml" \
           && -f "$TARGET_DIR/credentials/evidence-signing.yml" ]] \
          && printf 'complete'
      }
      When call scaffold "$1"
      The output should eq "complete"
    End
  End

  Describe "_cli.infra._init - p-local is bare (no endpoints)"
    It "writes only referential.yml, no endpoints"
      bare() {
        _cli.infra._init --profile p-local --dir "$TARGET_DIR" >/dev/null || return $?
        [[ -f "$TARGET_DIR/referential.yml" && -z "$(ls -A "$TARGET_DIR/endpoints")" ]] \
          && printf 'bare'
      }
      When call bare
      The output should eq "bare"
    End
  End

  Describe "_cli.infra._init - error branches"
    It "prints help for -h"
      When call _cli.infra._init -h
      The status should eq 0
      The output should include "infra"
    End

    It "rejects (2) an unknown option"
      When call _cli.infra._init --bogus
      The status should eq 2
      The stderr should include "unknown option"
    End

    It "rejects (2) an unknown profile"
      When call _cli.infra._init --profile p-ghost --dir "$TARGET_DIR"
      The status should eq 2
      The stderr should include "p-ghost"
    End

    It "rejects (2) --profile without a value"
      When call _cli.infra._init --profile
      The status should eq 2
      The stderr should include "--profile requires a value"
    End

    It "refuses (2) to overwrite an existing instance"
      init_twice() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR"
      }
      When call init_twice
      The status should eq 2
      The stderr should include "already exists"
    End
  End

  Describe "_cli.infra._validate"
    It "prints help for -h"
      When call _cli.infra._validate -h
      The status should eq 0
      The output should include "infra"
    End

    It "rejects (2) an unknown option"
      When call _cli.infra._validate --bogus
      The status should eq 2
      The stderr should include "unknown option"
    End

    It "fails closed without --dir or BRIK_INFRA_DIR"
      unset_validate() {
        unset BRIK_INFRA_DIR BRIK_INFRA_REPO
        _cli.infra._validate
      }
      When call unset_validate
      The status should not eq 0
      The stderr should include "brik infra init"
    End

    It "reports a scaffolded instance as valid (--dir)"
      Skip if "no JSON Schema validator on PATH" validator_missing
      validate_ok() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        _cli.infra._validate --dir "$TARGET_DIR"
      }
      When call validate_ok
      The status should eq 0
      The output should include "valid"
    End

    It "rejects (7) an instance with a broken endpoint"
      Skip if "no JSON Schema validator on PATH" validator_missing
      validate_broken() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        yq -i 'del(.url)' "$TARGET_DIR/endpoints/registry-candidate.yml"
        _cli.infra._validate --dir "$TARGET_DIR"
      }
      When call validate_broken
      The status should eq 7
      The stderr should include "invalid"
    End
  End

  Describe "_cli.infra._secrets"
    It "prints help for -h"
      When call _cli.infra._secrets -h
      The status should eq 0
      The output should include "infra"
    End

    It "rejects (2) an unknown option"
      When call _cli.infra._secrets --bogus
      The status should eq 2
      The stderr should include "unknown option"
    End

    It "lists pipeline and infra secrets (default list mode)"
      list_secrets() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        _cli.infra._secrets --dir "$TARGET_DIR"
      }
      When call list_secrets
      The status should eq 0
      The output should include "Pipeline-side secrets"
      The output should include "BRIK_REGISTRY_USER"
      The output should include "Infra-side secrets"
    End

    It "lists (none) for the infra section when there is no SecretManager"
      list_none() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        _cli.infra._secrets --dir "$TARGET_DIR"
      }
      When call list_none
      The output should include "(none)"
    End

    It "emits a JSON object (--json)"
      json_secrets() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        _cli.infra._secrets --dir "$TARGET_DIR" --json
      }
      When call json_secrets
      The status should eq 0
      The output should include "pipeline"
      The output should include "BRIK_REGISTRY_USER"
    End

    It "--check fails closed (4) when an expected variable is unset"
      check_missing() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        unset BRIK_REGISTRY_USER BRIK_REGISTRY_PASSWORD BRIK_GIT_TOKEN
        _cli.infra._secrets --dir "$TARGET_DIR" --check
      }
      When call check_missing
      The status should eq 4
      The stderr should include "missing required secret"
    End

    It "--check succeeds when every expected variable is set"
      check_ok() {
        _cli.infra._init --profile p-lab --dir "$TARGET_DIR" >/dev/null || return $?
        export BRIK_REGISTRY_USER=u BRIK_REGISTRY_PASSWORD=p BRIK_GIT_TOKEN=t
        _cli.infra._secrets --dir "$TARGET_DIR" --check
      }
      When call check_ok
      The status should eq 0
      The output should include "set"
    End

    It "fails closed without --dir or BRIK_INFRA_DIR"
      unset_secrets() {
        unset BRIK_INFRA_DIR BRIK_INFRA_REPO
        _cli.infra._secrets
      }
      When call unset_secrets
      The status should not eq 0
      The stderr should include "brik infra init"
    End
  End
End
