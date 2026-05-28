#shellcheck shell=bash
# Contract tests for the registry stage API (registry.stage.*).
#
# Concrete value tests live in spec/registry/registry_spec.sh. This
# harness adds the BEHAVIOURAL invariants from ADR-002 that any
# registry conforming to v1 must hold, regardless of which manifests
# are loaded.

Describe "registry.stage.* contract"
  Include "$BRIK_HOME/spec/unit/registry/contract/helpers.sh"
  Include "$BRIK_HOME/lib/registry/_loader.sh"
  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "scenario: builtin-only"
    setup() { contract.scenario.setup "builtin-only"; }
    cleanup() { contract.scenario.teardown; }
    Before 'setup'
    After 'cleanup'

    It "returns a non-empty stage list"
      When call registry.stage.list
      The status should equal 0
      The output should not equal ""
    End

    It "registry.stage.exists is true for every listed stage"
      check_each_stage_exists() {
        local id
        for id in $(registry.stage.list); do
          registry.stage.exists "$id" || { echo "missing: $id"; return 1; }
        done
      }
      When call check_each_stage_exists
      The status should equal 0
      The output should equal ""
    End

    It "registry.stage.exists is false for an unknown id"
      When call registry.stage.exists "definitely-not-a-stage-xyz"
      The status should not equal 0
    End

    It "every stage exposes module and function (dotted Bash names)"
      check_module_function() {
        local id m f
        for id in $(registry.stage.list); do
          m="$(registry.stage.module "$id")"
          f="$(registry.stage.function "$id")"
          [[ -n "$m" && "$m" == *.* ]] \
            || { echo "bad module: $id -> '$m'"; return 1; }
          [[ -n "$f" && "$f" == *.* ]] \
            || { echo "bad function: $id -> '$f'"; return 1; }
        done
      }
      When call check_module_function
      The status should equal 0
    End

    It "every stage advertises a placement slot"
      check_slot() {
        local id slot
        for id in $(registry.stage.list); do
          slot="$(registry.stage.placement_slot "$id")"
          [[ -n "$slot" ]] \
            || { echo "no placement.slot: $id"; return 1; }
        done
      }
      When call check_slot
      The status should equal 0
    End

    It "every stage gate_mode is one of blocking|opt_in"
      # Schema enum: schemas/registry/v1/stage.schema.json
      # gate.mode constrains the planner: "blocking" stages run on
      # every context allowed by gate.contexts; "opt_in" stages skip
      # unless gate.opt_in_flag was passed.
      check_gate_mode() {
        local id mode
        for id in $(registry.stage.list); do
          mode="$(registry.stage.gate_mode "$id")"
          case "$mode" in
            blocking|opt_in) ;;
            *) echo "bad gate.mode for $id: '$mode'"; return 1 ;;
          esac
        done
      }
      When call check_gate_mode
      The status should equal 0
    End

    It "opt_in stages declare a non-empty opt_in_flag"
      check_opt_in_flag() {
        local id mode flag
        for id in $(registry.stage.list); do
          mode="$(registry.stage.gate_mode "$id")"
          [[ "$mode" == "opt_in" ]] || continue
          flag="$(registry.stage.gate_opt_in_flag "$id")"
          [[ -n "$flag" ]] \
            || { echo "opt_in stage without opt_in_flag: $id"; return 1; }
        done
      }
      When call check_opt_in_flag
      The status should equal 0
    End

    It "registry.stage.runner_class returns one of the known classes"
      check_runner_class() {
        local id class
        for id in $(registry.stage.list); do
          class="$(registry.stage.runner_class "$id")"
          case "$class" in
            stack|base|scanner|analysis|deploy) ;;
            *) echo "bad runner.class for $id: '$class'"; return 1 ;;
          esac
        done
      }
      When call check_runner_class
      The status should equal 0
    End

    It "registry.stage.resolve_alias is idempotent for canonical ids"
      check_alias_idempotent() {
        local id canonical
        for id in $(registry.stage.list); do
          canonical="$(registry.stage.resolve_alias "$id")"
          [[ "$canonical" == "$id" ]] \
            || { echo "id changed under resolve_alias: $id -> $canonical"; return 1; }
        done
      }
      When call check_alias_idempotent
      The status should equal 0
    End
  End

  Describe "scenario: builtin+extension"
    setup() { contract.scenario.setup "builtin+extension"; }
    cleanup() { contract.scenario.teardown; }
    Before 'setup'
    After 'cleanup'

    It "lists the synthetic stage alongside the builtins"
      When call registry.stage.list
      The status should equal 0
      The output should include "contract-stage"
      The output should include "init"
    End

    It "exposes the same accessor surface for the synthetic stage"
      check_accessor_surface() {
        registry.stage.exists "contract-stage" || return 1
        [[ -n "$(registry.stage.module        contract-stage)" ]] || return 2
        [[ -n "$(registry.stage.function      contract-stage)" ]] || return 3
        [[ -n "$(registry.stage.placement_slot contract-stage)" ]] || return 4
        [[ -n "$(registry.stage.gate_mode     contract-stage)" ]] || return 5
        [[ -n "$(registry.stage.runner_class  contract-stage)" ]] || return 6
      }
      When call check_accessor_surface
      The status should equal 0
    End

    It "extends the builtin stage count by exactly one"
      count_stages() { registry.stage.list | wc -l | tr -d ' '; }
      When call count_stages
      The status should equal 0
      The output should equal "13"
    End

    It "preserves the topological order: contract-stage follows init"
      compare_ranks() {
        local stages init_pos cs_pos
        mapfile -t stages < <(registry.stage.list)
        local i
        for i in "${!stages[@]}"; do
          case "${stages[$i]}" in
            init)            init_pos="$i" ;;
            contract-stage)  cs_pos="$i" ;;
          esac
        done
        [[ -n "$init_pos" && -n "$cs_pos" ]] || { echo "missing init or contract-stage"; return 1; }
        (( cs_pos > init_pos )) || { echo "order broken: init=$init_pos contract-stage=$cs_pos"; return 1; }
      }
      When call compare_ranks
      The status should equal 0
    End
  End
End
