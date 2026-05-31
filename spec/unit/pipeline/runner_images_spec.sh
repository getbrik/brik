Describe "runner-images.sh"
  Include "$BRIK_PIPELINE_LIB/runner-images.sh"

  Describe "runner.resolve_image"
    It "resolves node 22 to the correct image"
      When call runner.resolve_image node 22
      The output should equal "ghcr.io/getbrik/brik-runner-node:22"
      The status should be success
    End

    It "resolves node 24 to the correct image"
      When call runner.resolve_image node 24
      The output should equal "ghcr.io/getbrik/brik-runner-node:24"
      The status should be success
    End

    It "resolves java 21 to the correct image"
      When call runner.resolve_image java 21
      The output should equal "ghcr.io/getbrik/brik-runner-java:21"
      The status should be success
    End

    It "resolves java 25 to the correct image"
      When call runner.resolve_image java 25
      The output should equal "ghcr.io/getbrik/brik-runner-java:25"
      The status should be success
    End

    It "resolves python 3.13 to the correct image"
      When call runner.resolve_image python 3.13
      The output should equal "ghcr.io/getbrik/brik-runner-python:3.13"
      The status should be success
    End

    It "resolves python 3.14 to the correct image"
      When call runner.resolve_image python 3.14
      The output should equal "ghcr.io/getbrik/brik-runner-python:3.14"
      The status should be success
    End

    It "resolves rust 1 to the correct image"
      When call runner.resolve_image rust 1
      The output should equal "ghcr.io/getbrik/brik-runner-rust:1"
      The status should be success
    End

    It "resolves dotnet 9.0 to the correct image"
      When call runner.resolve_image dotnet 9.0
      The output should equal "ghcr.io/getbrik/brik-runner-dotnet:9.0"
      The status should be success
    End

    It "resolves dotnet 10.0 to the correct image"
      When call runner.resolve_image dotnet 10.0
      The output should equal "ghcr.io/getbrik/brik-runner-dotnet:10.0"
      The status should be success
    End

    It "returns failure for 'base' (not a language stack -- use runner.base_image)"
      When call runner.resolve_image base 3.23
      The status should be failure
      The output should equal ""
    End
  End

  Describe "runner.base_image"
    It "returns the base runner image at the default tag"
      When call runner.base_image
      The output should equal "ghcr.io/getbrik/brik-runner-base:latest"
      The status should be success
    End

    It "honours BRIK_RUNNER_REGISTRY for the base image"
      BRIK_RUNNER_REGISTRY="registry.example.com/custom"
      When call runner.base_image
      The output should equal "registry.example.com/custom/brik-runner-base:latest"
    End

    # Parity guard: the fallback base tag must mirror the 'base' runner_class
    # tag in lib/registry/runner_classes.yml (the canonical map on the normal
    # path). Without this, the fallback and the registry could drift (the bug
    # this consolidation closed: fallback was '3.23' while the registry said
    # 'latest').
    It "matches the 'base' runner_class tag in runner_classes.yml"
      registry_base_tag() {
        yq -r '.classes.base.tag' "$BRIK_HOME/lib/registry/runner_classes.yml"
      }
      When call registry_base_tag
      The output should equal "$BRIK_RUNNER_BASE_DEFAULT_TAG"
    End
  End

  Describe "runner.resolve_stack_or_base"
    It "resolves a known stack to its image"
      When call runner.resolve_stack_or_base node 22
      The output should equal "ghcr.io/getbrik/brik-runner-node:22"
      The status should be success
    End

    It "falls back to the base image for stack 'auto'"
      When call runner.resolve_stack_or_base auto
      The output should equal "ghcr.io/getbrik/brik-runner-base:latest"
      The status should be success
    End

    It "falls back to the base image for an empty stack"
      When call runner.resolve_stack_or_base ""
      The output should equal "ghcr.io/getbrik/brik-runner-base:latest"
      The status should be success
    End

    It "falls back to the base image for an unknown stack (with a warning)"
      When call runner.resolve_stack_or_base golang 1.22
      The output should equal "ghcr.io/getbrik/brik-runner-base:latest"
      The status should be success
      The stderr should be present
    End
  End

  Describe "runner.resolve_image with defaults"
    It "resolves node without version to default (22)"
      When call runner.resolve_image node
      The output should equal "ghcr.io/getbrik/brik-runner-node:22"
      The status should be success
    End

    It "resolves java without version to default (21)"
      When call runner.resolve_image java
      The output should equal "ghcr.io/getbrik/brik-runner-java:21"
      The status should be success
    End

    It "resolves python without version to default (3.13)"
      When call runner.resolve_image python
      The output should equal "ghcr.io/getbrik/brik-runner-python:3.13"
      The status should be success
    End

    It "resolves rust without version to default (1)"
      When call runner.resolve_image rust
      The output should equal "ghcr.io/getbrik/brik-runner-rust:1"
      The status should be success
    End

    It "resolves dotnet without version to default (9.0)"
      When call runner.resolve_image dotnet
      The output should equal "ghcr.io/getbrik/brik-runner-dotnet:9.0"
      The status should be success
    End
  End

  Describe "runner.resolve_image with unknown stack/version"
    It "returns failure for unknown stack"
      When call runner.resolve_image golang 1.22
      The status should be failure
      The output should equal ""
    End

    It "returns failure for unknown version"
      When call runner.resolve_image node 99
      The status should be failure
      The output should equal ""
    End
  End

  Describe "BRIK_RUNNER_REGISTRY override"
    setup() {
      export BRIK_RUNNER_REGISTRY="registry.example.com/custom"
    }
    cleanup() {
      export BRIK_RUNNER_REGISTRY="ghcr.io/getbrik"
    }

    # Need to re-source with the override since variables are set at source time.
    # Instead, test the resolve function which uses the already-set variables.
    # The registry override only applies at source time, so we test the default behavior.
    It "uses the default registry when BRIK_RUNNER_REGISTRY is not overridden"
      When call runner.resolve_image node 22
      The output should start with "ghcr.io/getbrik/"
    End
  End
End
