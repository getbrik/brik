Describe "cli.plan.run - writer + validate-only branches"
  # Unit-level coverage for the cli.plan.run branches that need a
  # controlled plan_writer or a controlled validator set:
  #   - plan_writer.write failure path (rm temp + INVALID_INPUT)
  #   - --validate-only jv branch (valid + schema-failure)
  #   - --validate-only check-jsonschema fallback branch
  #   - --validate-only missing-dependency branch
  #
  # Sourcing the module directly (rather than driving bin/brik) lets the
  # tests override plan_writer.write and the `command` builtin so the
  # rarely-hit validator fallbacks are exercised deterministically.

  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/plan.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_ws() {
    mock.infra.setup
    PLAN_WS="$(mktemp -d)"
    ( cd "$PLAN_WS" && git init -q && git config user.email t@t \
        && git config user.name t && : > marker && git add -A \
        && git commit -q -m baseline )
  }
  cleanup_ws() {
    rm -rf "$PLAN_WS"
    mock.infra.teardown
  }
  Before 'setup_ws'
  After 'cleanup_ws'

  # Replace plan_writer.write with a stub and mark the module as already
  # loaded so brik.use inside cli.plan.run does not re-source the real
  # implementation over the stub. $1 is the stub function body.
  stub_writer() {
    export _BRIK_MODULE_PLANNING_PLAN_WRITER_LOADED=1
    eval "plan_writer.write() { $1 }"
  }

  Describe "plan_writer.write failure"
    It "exits INVALID_INPUT when the writer returns non-zero"
      # Override the writer with a stub that fails; cli.plan.run must
      # remove the temp file and return INVALID_INPUT.
      stub_writer 'return 1;'
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe \
        --out "$PLAN_WS/.brik-logs/plan.json"
      The status should equal 2
      The path "$PLAN_WS/.brik-logs/plan.json" should not be exist
    End
  End

  Describe "--validate-only jv branch"
    It "reports a valid plan against the schema"
      if ! command -v jv >/dev/null 2>&1; then
        Skip "jv not on PATH"
      fi
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 0
      The output should include "valid against schema"
    End

    It "exits INVALID_INPUT when the plan fails schema validation"
      if ! command -v jv >/dev/null 2>&1; then
        Skip "jv not on PATH"
      fi
      # The stubbed writer emits a plan that misses every required
      # property, so jv rejects it.
      stub_writer "printf '%s' '{\"bogus\":true}'; return 0;"
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 2
      The stderr should include "schema validation failed"
    End
  End

  Describe "--validate-only check-jsonschema fallback"
    # Hide jv via a command-builtin override so cli.plan.run falls
    # through to the check-jsonschema branch.
    hide_jv() {
      command() {
        if [ "$1" = "-v" ] && [ "$2" = "jv" ]; then return 1; fi
        builtin command "$@"
      }
    }

    It "validates with check-jsonschema when jv is absent"
      if ! builtin command -v check-jsonschema >/dev/null 2>&1; then
        Skip "check-jsonschema not on PATH"
      fi
      hide_jv
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 0
      The output should include "valid against schema"
    End

    It "exits INVALID_INPUT when check-jsonschema rejects the plan"
      if ! builtin command -v check-jsonschema >/dev/null 2>&1; then
        Skip "check-jsonschema not on PATH"
      fi
      hide_jv
      stub_writer "printf '%s' '{\"bogus\":true}'; return 0;"
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 2
    End
  End

  Describe "--validate-only missing validator"
    It "exits MISSING_DEP when no JSON Schema validator is available"
      # Hide both jv and check-jsonschema.
      command() {
        case "$1 $2" in
          "-v jv"|"-v check-jsonschema") return 1 ;;
          *) builtin command "$@" ;;
        esac
      }
      When call cli.plan.run --workspace "$PLAN_WS" --mode safe --validate-only
      The status should equal 3
      The stderr should include "no JSON Schema validator available"
    End
  End
End
