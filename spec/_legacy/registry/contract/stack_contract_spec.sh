#shellcheck shell=bash
# Contract tests for the registry stack API (registry.stack.*).
#
# These tests do NOT pin specific values (those live in spec/registry/
# registry_spec.sh). They pin BEHAVIOURAL invariants that any registry
# satisfying ADR-002 must hold, regardless of which manifests are loaded.
#
# Two scenarios:
#   - builtin-only: lib/registry/manifests/* alone
#   - builtin+extension: builtins plus a synthetic contract-stack

Describe "registry.stack.* contract"
  Include "$BRIK_HOME/spec/_legacy/registry/contract/helpers.sh"
  Include "$BRIK_HOME/lib/registry/_loader.sh"
  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "scenario: builtin-only"
    setup() { contract.scenario.setup "builtin-only"; }
    cleanup() { contract.scenario.teardown; }
    Before 'setup'
    After 'cleanup'

    It "returns a non-empty stack list"
      When call registry.stack.list
      The status should equal 0
      The output should not equal ""
    End

    It "registry.stack.exists is true for every listed stack"
      check_each_stack_exists() {
        local id
        for id in $(registry.stack.list); do
          registry.stack.exists "$id" || { echo "missing: $id"; return 1; }
        done
      }
      When call check_each_stack_exists
      The status should equal 0
      The output should equal ""
    End

    It "registry.stack.exists is false for an unknown id"
      When call registry.stack.exists "definitely-not-a-stack-xyz"
      The status should not equal 0
    End

    It "every stack exposes at least one literal or glob marker"
      # Stacks can advertise detection markers via spec.detect.markers.any
      # (literal filenames) or spec.detect.markers.glob (shell globs).
      # The dotnet stack uses .glob only, others use .any only -- the
      # invariant the contract pins is that AT LEAST ONE of the two is
      # non-empty so detection has something to match against.
      check_markers_any_or_glob() {
        local id literal glob
        for id in $(registry.stack.list); do
          literal="$(registry.stack.markers "$id")"
          glob="$(registry.stack.markers_glob "$id")"
          [[ -n "$literal" || -n "$glob" ]] \
            || { echo "no markers (any or glob): $id"; return 1; }
        done
      }
      When call check_markers_any_or_glob
      The status should equal 0
    End

    It "every stack resolves runner_image to a non-empty fully-qualified ref"
      # registry.stack.runner_image returns the bare image (without a
      # version tag); the version comes from runner_default_version.
      # The contract here is "image must look like a reachable ref":
      # non-empty and contains a '/' (org/name) at minimum.
      check_runner_image() {
        local id img
        for id in $(registry.stack.list); do
          img="$(registry.stack.runner_image "$id")"
          [[ -n "$img" && "$img" == */* ]] \
            || { echo "bad image: $id -> '$img'"; return 1; }
        done
      }
      When call check_runner_image
      The status should equal 0
    End

    It "registry.stack.runner_default_version is one of the declared versions"
      check_default_in_versions() {
        local id default versions
        for id in $(registry.stack.list); do
          default="$(registry.stack.runner_default_version "$id")"
          versions="$(registry.stack.runner_versions "$id" | tr '\n' ' ')"
          [[ " $versions " == *" $default "* ]] \
            || { echo "default '$default' not in '$versions' for $id"; return 1; }
        done
      }
      When call check_default_in_versions
      The status should equal 0
    End

    It "registry.stack.api_required lists at least one function"
      check_api_required_nonempty() {
        local id
        for id in $(registry.stack.list); do
          [[ -n "$(registry.stack.api_required "$id")" ]] \
            || { echo "empty api.required: $id"; return 1; }
        done
      }
      When call check_api_required_nonempty
      The status should equal 0
    End

    It "registry.stack.detect_from_framework returns rc != 0 on unknown name"
      When call registry.stack.detect_from_framework "definitely-not-a-framework-xyz"
      The status should not equal 0
    End
  End

  Describe "scenario: builtin+extension"
    setup() { contract.scenario.setup "builtin+extension"; }
    cleanup() { contract.scenario.teardown; }
    Before 'setup'
    After 'cleanup'

    It "lists the synthetic stack alongside the builtins"
      When call registry.stack.list
      The status should equal 0
      The output should include "contract-stack"
      The output should include "node"
    End

    It "exposes the same accessor surface for the synthetic stack"
      check_accessor_surface() {
        registry.stack.exists "contract-stack" || return 1
        [[ -n "$(registry.stack.markers      contract-stack)" ]] || return 2
        [[ -n "$(registry.stack.cache_paths  contract-stack)" ]] || return 3
        [[ -n "$(registry.stack.runner_image contract-stack)" ]] || return 4
        [[ -n "$(registry.stack.api_required contract-stack)" ]] || return 5
      }
      When call check_accessor_surface
      The status should equal 0
    End

    It "preserves the builtin stacks count + 1"
      count_stacks() { registry.stack.list | wc -l | tr -d ' '; }
      When call count_stacks
      The status should equal 0
      The output should equal "7"
    End
  End
End
