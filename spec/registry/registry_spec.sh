#shellcheck shell=bash
# Contract for lib/registry/registry.sh + lib/registry/_loader.sh
#
# Validates the Definition of Done of D.1 (registry sans changement
# fonctionnel) per docs/chantiers/20260518_refonte_architecture-extensive-phases.md.
#
# Prerequisites: lib/registry/cache/registry.json must exist (run
# scripts/compile-registry.sh first or rely on the spec_helper).

Describe "lib/registry/registry.sh"
  # Ensure the cache is built before the suite runs (idempotent if up to date).
  BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'

  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "registry.stack.list"
    It "returns the 6 builtin stacks"
      When call registry.stack.list
      The status should be success
      The line 1 of stdout should equal "docker"
      The line 2 of stdout should equal "dotnet"
      The line 3 of stdout should equal "java"
      The line 4 of stdout should equal "node"
      The line 5 of stdout should equal "python"
      The line 6 of stdout should equal "rust"
    End
  End

  Describe "registry.stack.markers"
    It "returns the literal markers for node"
      When call registry.stack.markers node
      The status should be success
      The output should equal "package.json"
    End

    It "returns the 3 markers for java"
      When call registry.stack.markers java
      The line 1 should equal "pom.xml"
      The line 2 should equal "build.gradle"
      The line 3 should equal "build.gradle.kts"
    End

    It "returns the 3 markers for python"
      When call registry.stack.markers python
      The line 1 should equal "requirements.txt"
      The line 2 should equal "setup.py"
      The line 3 should equal "pyproject.toml"
    End
  End

  Describe "registry.stack.markers_glob"
    It "returns the 2 glob markers for dotnet"
      When call registry.stack.markers_glob dotnet
      The line 1 should equal "*.csproj"
      The line 2 should equal "*.sln"
    End

    It "returns empty for stacks without glob markers"
      When call registry.stack.markers_glob node
      The status should be success
      The output should equal ""
    End
  End

  Describe "registry.stack.cache_paths"
    It "returns the .npm path for node"
      When call registry.stack.cache_paths node
      The output should equal ".npm"
    End

    It "returns the 3 Java cache paths"
      When call registry.stack.cache_paths java
      The line 1 should equal ".m2/repository"
      The line 2 should equal ".gradle/caches"
      The line 3 should equal ".gradle/wrapper"
    End
  End

  Describe "registry.stack.runner_image"
    It "returns the ghcr image for node"
      When call registry.stack.runner_image node
      The output should equal "ghcr.io/getbrik/brik-runner-node"
    End
  End

  Describe "registry.stack.runner_default_version"
    It "returns 22 for node"
      When call registry.stack.runner_default_version node
      The output should equal "22"
    End

    It "returns 21 for java"
      When call registry.stack.runner_default_version java
      The output should equal "21"
    End

    It "returns 3.13 for python"
      When call registry.stack.runner_default_version python
      The output should equal "3.13"
    End
  End

  Describe "registry.stack.runner_versions"
    It "returns 22 and 24 for node"
      When call registry.stack.runner_versions node
      The line 1 should equal "22"
      The line 2 should equal "24"
    End
  End

  Describe "registry.stack.display_name"
    It "returns the displayName for node"
      When call registry.stack.display_name node
      The output should equal "Node.js"
    End

    It "fails for an unknown stack id"
      When call registry.stack.display_name bogus
      The status should be failure
    End
  End

  Describe "registry.stack.module"
    It "returns the bash module path for node"
      When call registry.stack.module node
      The output should equal "stacks.node"
    End
  End

  Describe "registry.stack.api_required"
    It "lists every required function for node"
      When call registry.stack.api_required node
      The output should include "stacks.node.build"
      The output should include "stacks.node.test"
    End
  End

  Describe "registry.stack.api_optional"
    It "lists optional functions for node"
      When call registry.stack.api_optional node
      The status should be success
      The output should include "stacks.node.install"
    End
  End

  Describe "registry.stack.impact_source"
    It "lists source-impact globs for node"
      When call registry.stack.impact_source node
      The output should include "**/*.ts"
    End
  End

  Describe "registry.stack.impact_test"
    It "lists test-impact globs for node"
      When call registry.stack.impact_test node
      The output should be present
    End
  End

  Describe "registry.stack.impact_build"
    It "lists build-impact globs for node"
      When call registry.stack.impact_build node
      The output should include "package-lock.json"
    End
  End

  Describe "registry.stack.doctor_tools"
    It "lists doctor probes for node"
      When call registry.stack.doctor_tools node
      The output should include "node"
    End
  End

  Describe "registry.stack.artifact_output_dirs"
    It "lists default artifact dirs for node"
      When call registry.stack.artifact_output_dirs node
      The status should be success
      The output should include "dist"
    End
  End

  Describe "registry.stack.artifact_patterns"
    It "lists default artifact patterns for node"
      When call registry.stack.artifact_patterns node
      The status should be success
      The output should include "*.tgz"
    End
  End

  Describe "registry.stack.detect_from_framework"
    It "maps pytest to python"
      When call registry.stack.detect_from_framework pytest
      The output should equal "python"
    End

    It "maps jest to node"
      When call registry.stack.detect_from_framework jest
      The output should equal "node"
    End

    It "maps maven to java"
      When call registry.stack.detect_from_framework maven
      The output should equal "java"
    End

    It "returns non-zero for unknown framework"
      When call registry.stack.detect_from_framework unknownframework
      The status should be failure
    End
  End

  Describe "registry.stack.detect"
    Context "with a package.json marker"
      tmp_ws() {
        BRIK_TEST_WS=$(mktemp -d)
        touch "$BRIK_TEST_WS/package.json"
      }
      BeforeEach 'tmp_ws'

      It "detects node"
        When call registry.stack.detect "$BRIK_TEST_WS"
        The output should equal "node"
      End
    End

    Context "with a Cargo.toml marker"
      tmp_ws() {
        BRIK_TEST_WS=$(mktemp -d)
        touch "$BRIK_TEST_WS/Cargo.toml"
      }
      BeforeEach 'tmp_ws'

      It "detects rust"
        When call registry.stack.detect "$BRIK_TEST_WS"
        The output should equal "rust"
      End
    End

    Context "with a .csproj glob marker"
      tmp_ws() {
        BRIK_TEST_WS=$(mktemp -d)
        touch "$BRIK_TEST_WS/MyProject.csproj"
      }
      BeforeEach 'tmp_ws'

      It "detects dotnet via glob"
        When call registry.stack.detect "$BRIK_TEST_WS"
        The output should equal "dotnet"
      End
    End

    Context "with an empty workspace"
      tmp_ws() { BRIK_TEST_WS=$(mktemp -d); }
      BeforeEach 'tmp_ws'

      It "returns failure"
        When call registry.stack.detect "$BRIK_TEST_WS"
        The status should be failure
      End
    End
  End

  Describe "registry.stage.list"
    It "returns the 12 builtin stages in canonical order"
      When call registry.stage.list
      The status should be success
      The line 1  of stdout should equal "init"
      The line 2  of stdout should equal "release"
      The line 3  of stdout should equal "build"
      The line 4  of stdout should equal "lint"
      The line 5  of stdout should equal "sast"
      The line 6  of stdout should equal "scan"
      The line 7  of stdout should equal "test"
      The line 8  of stdout should equal "package"
      The line 9  of stdout should equal "container-scan"
      The line 10 of stdout should equal "promote"
      The line 11 of stdout should equal "deploy"
      The line 12 of stdout should equal "notify"
    End
  End

  Describe "registry.stage.function"
    It "returns the bash function for init"
      When call registry.stage.function init
      The output should equal "stages.init"
    End

    It "returns stages.container_scan for container-scan (kebab to snake)"
      When call registry.stage.function container-scan
      The output should equal "stages.container_scan"
    End
  End

  Describe "registry.stage.resolve_alias"
    It "resolves quality to lint (legacy alias)"
      When call registry.stage.resolve_alias quality
      The output should equal "lint"
    End

    It "resolves security to scan (legacy alias)"
      When call registry.stage.resolve_alias security
      The output should equal "scan"
    End

    It "returns the input unchanged for canonical names"
      When call registry.stage.resolve_alias init
      The output should equal "init"
    End
  End

  Describe "registry.stage.function via alias"
    It "returns stages.lint when called with quality"
      When call registry.stage.function quality
      The output should equal "stages.lint"
    End

    It "returns stages.scan when called with security"
      When call registry.stage.function security
      The output should equal "stages.scan"
    End
  End

  Describe "registry.stage.placement_slot"
    It "init is in the init slot"
      When call registry.stage.placement_slot init
      The output should equal "init"
    End

    It "lint is in the verify slot"
      When call registry.stage.placement_slot lint
      The output should equal "verify"
    End

    It "container-scan is in the post-package slot"
      When call registry.stage.placement_slot container-scan
      The output should equal "post-package"
    End
  End

  Describe "registry.stage.placement_group"
    It "lint is in the verify group"
      When call registry.stage.placement_group lint
      The output should equal "verify"
    End

    It "scan is in the verify group"
      When call registry.stage.placement_group scan
      The output should equal "verify"
    End

    It "test is in the verify group"
      When call registry.stage.placement_group test
      The output should equal "verify"
    End

    It "init has no group"
      When call registry.stage.placement_group init
      The output should equal ""
    End
  End

  Describe "registry.stage.runner_class"
    It "init is base"
      When call registry.stage.runner_class init
      The output should equal "base"
    End

    It "build is stack"
      When call registry.stage.runner_class build
      The output should equal "stack"
    End

    It "sast is analysis"
      When call registry.stage.runner_class sast
      The output should equal "analysis"
    End

    It "scan is scanner"
      When call registry.stage.runner_class scan
      The output should equal "scanner"
    End

    It "deploy is deploy"
      When call registry.stage.runner_class deploy
      The output should equal "deploy"
    End
  End

  Describe "registry.stage.gate_mode"
    It "init is blocking"
      When call registry.stage.gate_mode init
      The output should equal "blocking"
    End

    It "release is opt_in"
      When call registry.stage.gate_mode release
      The output should equal "opt_in"
    End

    It "package is opt_in"
      When call registry.stage.gate_mode package
      The output should equal "opt_in"
    End

    It "deploy is opt_in"
      When call registry.stage.gate_mode deploy
      The output should equal "opt_in"
    End

    It "build is blocking"
      When call registry.stage.gate_mode build
      The output should equal "blocking"
    End
  End

  Describe "registry.stage.gate_opt_in_flag"
    It "release uses --with-release"
      When call registry.stage.gate_opt_in_flag release
      The output should equal "--with-release"
    End

    It "package uses --with-package"
      When call registry.stage.gate_opt_in_flag package
      The output should equal "--with-package"
    End

    It "deploy uses --with-deploy"
      When call registry.stage.gate_opt_in_flag deploy
      The output should equal "--with-deploy"
    End

    It "build has no opt-in flag (blocking)"
      When call registry.stage.gate_opt_in_flag build
      The output should equal ""
    End
  End

  Describe "registry.stage.is_destructive"
    It "release is destructive"
      When call registry.stage.is_destructive release
      The status should be success
    End

    It "package is destructive"
      When call registry.stage.is_destructive package
      The status should be success
    End

    It "deploy is destructive"
      When call registry.stage.is_destructive deploy
      The status should be success
    End

    It "notify is destructive"
      When call registry.stage.is_destructive notify
      The status should be success
    End

    It "build is NOT destructive"
      When call registry.stage.is_destructive build
      The status should be failure
    End

    It "init is NOT destructive"
      When call registry.stage.is_destructive init
      The status should be failure
    End

    It "lint is NOT destructive"
      When call registry.stage.is_destructive lint
      The status should be failure
    End
  End

  Describe "registry.stage.after (placement.after)"
    It "init has no predecessors"
      When call registry.stage.after init
      The output should equal ""
    End

    It "release comes after init"
      When call registry.stage.after release
      The output should equal "init"
    End

    It "package comes after lint sast scan test"
      When call registry.stage.after package
      The line 1 should equal "lint"
      The line 2 should equal "sast"
      The line 3 should equal "scan"
      The line 4 should equal "test"
    End
  End

  Describe "registry.stage.gate_contexts"
    It "release only runs in release context"
      When call registry.stage.gate_contexts release
      The output should equal "release"
    End

    It "build runs in snapshot and release contexts"
      When call registry.stage.gate_contexts build
      The line 1 should equal "snapshot"
      The line 2 should equal "release"
    End
  End

  Describe "registry.stage.aliases"
    It "lint has the quality alias"
      When call registry.stage.aliases lint
      The output should equal "quality"
    End

    It "scan has the security alias"
      When call registry.stage.aliases scan
      The output should equal "security"
    End

    It "init has no aliases"
      When call registry.stage.aliases init
      The output should equal ""
    End
  End

  Describe "registry.stack.exists"
    It "returns success for known stack"
      When call registry.stack.exists node
      The status should be success
    End

    It "returns BRIK_EXIT_INVALID_INPUT (64) for unknown stack"
      When call registry.stack.exists unknown_stack_xyz
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
    End
  End

  Describe "registry.stage.exists"
    It "returns success for known stage"
      When call registry.stage.exists init
      The status should be success
    End

    It "returns success for known alias"
      When call registry.stage.exists quality
      The status should be success
    End

    It "returns BRIK_EXIT_INVALID_INPUT (64) for unknown stage"
      When call registry.stage.exists unknown_stage_xyz
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
    End
  End
End
