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
  End

  # Each scaffolded profile must pass its own validation: the scaffolds
  # are the reference instances of the referential spec.
  Describe "scaffolds are self-validating"
    Parameters
      p-open
      p-entreprise
      p-lab
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
