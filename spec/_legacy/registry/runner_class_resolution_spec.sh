#shellcheck shell=bash
# Contract for lib/registry/runner_classes.yml + lib/registry/registry.sh
# runner_class helpers.
#
# Validates the Definition of Done of Lot 1 of
# docs/chantiers/20260526_pipeline-invariants-centralization.md:
#   - runner_classes.yml exists with 5 declared classes
#   - registry.runner_class.image <class> resolves to the canonical OCI ref
#   - the 'stack' class is dynamic (reads BRIK_CI_IMAGE)
#   - every spec.runner.class declared in manifests/stages/*.yml is known

Describe "lib/registry/registry.sh - runner_class helpers"
  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "registry.runner_class.image"
    It "resolves 'base' to the brik-runner-base image"
      When call registry.runner_class.image base
      The status should be success
      The output should equal "ghcr.io/getbrik/brik-runner-base:latest"
    End

    It "resolves 'analysis' to the brik-runner-analysis image"
      When call registry.runner_class.image analysis
      The status should be success
      The output should equal "ghcr.io/getbrik/brik-runner-analysis:latest"
    End

    It "resolves 'scanner' to the brik-runner-scanner image"
      When call registry.runner_class.image scanner
      The status should be success
      The output should equal "ghcr.io/getbrik/brik-runner-scanner:latest"
    End

    It "resolves 'deploy' to the brik-runner-deploy image"
      When call registry.runner_class.image deploy
      The status should be success
      The output should equal "ghcr.io/getbrik/brik-runner-deploy:latest"
    End

    Context "the dynamic 'stack' class"
      It "returns BRIK_CI_IMAGE when the env var is set"
        BRIK_CI_IMAGE="ghcr.io/getbrik/brik-runner-node:22"
        When call registry.runner_class.image stack
        The status should be success
        The output should equal "ghcr.io/getbrik/brik-runner-node:22"
      End

      It "fails when BRIK_CI_IMAGE is unset"
        unset BRIK_CI_IMAGE
        When call registry.runner_class.image stack
        The status should be failure
        The stderr should not equal ""
      End
    End

    It "fails for an unknown class with a diagnostic message"
      When call registry.runner_class.image bogus-class
      The status should be failure
      The stderr should include "bogus-class"
    End

    It "fails when called without arguments"
      When call registry.runner_class.image
      The status should be failure
      The stderr should include "required"
    End
  End

  Describe "registry.runner_class.list"
    It "returns the 5 declared classes"
      When call registry.runner_class.list
      The status should be success
      The lines of output should equal 5
    End

    It "includes 'base'"
      When call registry.runner_class.list
      The output should include "base"
    End

    It "includes 'stack'"
      When call registry.runner_class.list
      The output should include "stack"
    End

    It "includes 'analysis'"
      When call registry.runner_class.list
      The output should include "analysis"
    End

    It "includes 'scanner'"
      When call registry.runner_class.list
      The output should include "scanner"
    End

    It "includes 'deploy'"
      When call registry.runner_class.list
      The output should include "deploy"
    End
  End

  Describe "manifest coherence"
    # Every spec.runner.class declared in lib/registry/manifests/stages/*.yml
    # must be resolvable via registry.runner_class.image. Guards against the
    # drift where a new manifest references a class that was never added to
    # runner_classes.yml.
    It "every spec.runner.class in stages/*.yml resolves to an image"
      check_all_classes() {
        local manifest class rc=0
        for manifest in "$BRIK_HOME"/lib/registry/manifests/stages/*.yml; do
          class="$(yq -r '.spec.runner.class' "$manifest")"
          # Dummy value for the dynamic 'stack' class so resolution succeeds.
          BRIK_CI_IMAGE="dummy:test" \
            registry.runner_class.image "$class" >/dev/null 2>&1 || {
              printf 'class %s (used by %s) not declared in runner_classes.yml\n' \
                "$class" "$(basename "$manifest")"
              rc=1
            }
        done
        return "$rc"
      }
      When call check_all_classes
      The status should be success
    End
  End
End
