Describe "brik infra"
  # Helper: returns 0 when no JSON Schema validator is on PATH.
  validator_missing() {
    ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1
  }

  setup_dir() { TARGET_DIR="$(mktemp -d)"; }
  cleanup_dir() { rm -rf "$TARGET_DIR"; unset TARGET_DIR; }
  Before 'setup_dir'
  After 'cleanup_dir'

  Describe "argument handling"
    It "rejects (2) a missing subcommand"
      When run script "$BRIK_BIN" infra
      The status should equal 2
      The stderr should include "init"
    End

    It "rejects (2) an unknown subcommand"
      When run script "$BRIK_BIN" infra frobnicate
      The status should equal 2
      The stderr should include "frobnicate"
    End

    It "rejects (2) an unknown profile"
      When run script "$BRIK_BIN" infra init --profile p-ghost --dir "$TARGET_DIR"
      The status should equal 2
      The stderr should include "p-ghost"
    End
  End

  Describe "brik infra init"
    It "refuses (2) to overwrite an existing instance"
      init_twice() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR"
      }
      When call init_twice
      The status should equal 2
      The stderr should include "already exists"
    End

    It "copies the kind schemas into the instance"
      When run script "$BRIK_BIN" infra init --profile p-open --dir "$TARGET_DIR"
      The status should be success
      The output should include "$TARGET_DIR"
      The path "$TARGET_DIR/schemas/registry.schema.json" should be file
    End

    It "scaffolds into a dedicated dir, not the project root"
      init_default_dir() {
        cd "$TARGET_DIR" || return 1
        "$BRIK_BIN" infra init --profile p-local >/dev/null 2>&1 || return $?
        # The referential lands in a dedicated subdir, never beside the code.
        [[ -f "$TARGET_DIR/.brik/infra/referential.yml" && ! -f "$TARGET_DIR/referential.yml" ]] \
          && printf 'isolated'
      }
      When call init_default_dir
      The output should equal "isolated"
    End
  End

  # Each scaffolded profile must pass its own validation: the scaffolds
  # are the reference instances of the referential spec.
  Describe "scaffolds are self-validating"
    Parameters
      p-open
      p-entreprise
      p-lab
      p-local
    End

    It "brik infra init --profile $1 produces a valid instance"
      scaffold_and_validate() {
        "$BRIK_BIN" infra init --profile "$1" --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        "$BRIK_BIN" infra validate --dir "$TARGET_DIR"
      }
      When call scaffold_and_validate "$1"
      The status should be success
      The output should include "valid"
    End
  End

  # brik infra secrets -- derive the env:// variables an operator must provision,
  # BY TARGET (the operated endpoints' credentials), not by --environment (PD3).
  # pipeline-side = credential refs; infra-side = the SecretManager bootstrap
  # token. file:// has no variable; bao:// resolves through the manager (ignored).
  Describe "brik infra secrets"
    It "lists the pipeline-side env:// secrets (file:// excluded)"
      secrets_lab() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        "$BRIK_BIN" infra secrets --dir "$TARGET_DIR"
      }
      When call secrets_lab
      The status should be success
      The output should include "BRIK_REGISTRY_USER"
      The output should include "BRIK_REGISTRY_PASSWORD"
      The output should include "BRIK_GIT_TOKEN"
      # evidence-signing is file:// in p-lab -> no environment variable.
      The output should not include "evidence_signing_key"
    End

    It "classifies the SecretManager bootstrap token as infra-side (bao:// creds ignored)"
      secrets_ent() {
        "$BRIK_BIN" infra init --profile p-entreprise --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        "$BRIK_BIN" infra secrets --dir "$TARGET_DIR" --json | jq -c '{p: (.pipeline | length), i: .infra}'
      }
      When call secrets_ent
      The status should be success
      # p-entreprise credentials are all bao:// -> nothing pipeline-side; only the
      # OpenBAO bootstrap token is an env var.
      The output should equal '{"p":0,"i":["BAO_TOKEN"]}'
    End

    It "emits a JSON object with sorted pipeline and infra arrays (--json)"
      secrets_json() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        "$BRIK_BIN" infra secrets --dir "$TARGET_DIR" --json | jq -r '.pipeline | join(",")'
      }
      When call secrets_json
      The output should equal "BRIK_GIT_TOKEN,BRIK_REGISTRY_PASSWORD,BRIK_REGISTRY_USER"
    End

    It "--check fails closed (4) when an expected variable is unset"
      check_missing() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        unset BRIK_REGISTRY_USER BRIK_REGISTRY_PASSWORD BRIK_GIT_TOKEN
        "$BRIK_BIN" infra secrets --dir "$TARGET_DIR" --check
      }
      When call check_missing
      The status should equal 4
      The stderr should include "BRIK_GIT_TOKEN"
    End

    It "--check succeeds when every expected variable is set"
      check_ok() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        export BRIK_REGISTRY_USER=u BRIK_REGISTRY_PASSWORD=p BRIK_GIT_TOKEN=t
        "$BRIK_BIN" infra secrets --dir "$TARGET_DIR" --check
      }
      When call check_ok
      The status should be success
      The output should include "set"
    End

    It "fails closed (4) without --dir or BRIK_INFRA_DIR"
      When run script "$BRIK_BIN" infra secrets
      The status should equal 4
      The stderr should include "brik infra init"
    End
  End

  Describe "brik infra validate"
    It "fails closed (4) without --dir, BRIK_INFRA_DIR or BRIK_INFRA_REPO"
      When run script "$BRIK_BIN" infra validate
      The status should equal 4
      The stderr should include "brik infra init"
    End

    It "rejects (7) an invalid instance"
      Skip if "no JSON Schema validator on PATH" validator_missing
      validate_broken() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        yq -i 'del(.url)' "$TARGET_DIR/endpoints/registry-candidate.yml"
        "$BRIK_BIN" infra validate --dir "$TARGET_DIR"
      }
      When call validate_broken
      The status should equal 7
      The stderr should include "invalid"
    End

    It "honors BRIK_INFRA_DIR when --dir is not given"
      validate_env_dir() {
        "$BRIK_BIN" infra init --profile p-lab --dir "$TARGET_DIR" >/dev/null 2>&1 || return $?
        BRIK_INFRA_DIR="$TARGET_DIR" "$BRIK_BIN" infra validate
      }
      When call validate_env_dir
      The status should be success
      The output should include "valid"
    End
  End
End
