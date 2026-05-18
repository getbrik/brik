#shellcheck shell=bash
# Contract for lib/registry/_validator.sh
#
# Validates that the registry validator accepts conforming manifests and
# rejects malformed ones with a stable exit code. Per ADR-002 mechanism 1.

Describe "lib/registry/_validator.sh"
  Include "$BRIK_HOME/lib/registry/_validator.sh"

  Describe "registry.validate_manifest accepts builtin manifests"
    Parameters
      "node"          "stacks/node.yml"
      "java"          "stacks/java.yml"
      "python"        "stacks/python.yml"
      "dotnet"        "stacks/dotnet.yml"
      "rust"          "stacks/rust.yml"
      "docker"        "stacks/docker.yml"
      "init"          "stages/init.yml"
      "release"       "stages/release.yml"
      "build"         "stages/build.yml"
      "lint"          "stages/lint.yml"
      "sast"          "stages/sast.yml"
      "scan"          "stages/scan.yml"
      "test"          "stages/test.yml"
      "package"       "stages/package.yml"
      "container-scan" "stages/container-scan.yml"
      "deploy"        "stages/deploy.yml"
      "notify"        "stages/notify.yml"
    End

    Example "$1"
      When call registry.validate_manifest "$BRIK_HOME/lib/registry/manifests/$2"
      The status should be success
    End
  End

  Describe "registry.validate_all_manifests"
    It "passes on the 17 builtin manifests"
      When call registry.validate_all_manifests
      The status should be success
      The output should include "validated: 17/17"
    End
  End

  Describe "rejects malformed manifests"
    setup_bad_apiversion() {
      BRIK_TEST_BAD=$(mktemp -d)
      cat > "$BRIK_TEST_BAD/bad.yml" <<YAML
kind: Stack
metadata: {id: badone, displayName: Bad}
spec:
  detect: {markers: {any: [foo]}}
  runner: {image: ghcr.io/foo/bar, defaultVersion: "1", versions: ["1"]}
  api: {module: stacks.bad, required: [stacks.bad.build]}
YAML
    }
    BeforeEach 'setup_bad_apiversion'

    It "rejects manifest without apiVersion"
      When call registry.validate_manifest "$BRIK_TEST_BAD/bad.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "manifest invalid"
    End
  End

  Describe "rejects bad id pattern"
    setup_bad_id() {
      BRIK_TEST_BADID=$(mktemp -d)
      cat > "$BRIK_TEST_BADID/badid.yml" <<YAML
apiVersion: brik.dev/v1
kind: Stack
metadata: {id: NodeJS, displayName: Bad}
spec:
  detect: {markers: {any: [foo]}}
  runner: {image: ghcr.io/foo/bar, defaultVersion: "1", versions: ["1"]}
  api: {module: stacks.bad, required: [stacks.bad.build]}
YAML
    }
    BeforeEach 'setup_bad_id'

    It "rejects uppercase letters in metadata.id"
      When call registry.validate_manifest "$BRIK_TEST_BADID/badid.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should be present
    End
  End

  Describe "rejects opt_in stage without opt_in_flag"
    setup_bad_gate() {
      BRIK_TEST_BADGATE=$(mktemp -d)
      cat > "$BRIK_TEST_BADGATE/badgate.yml" <<YAML
apiVersion: brik.dev/v1
kind: Stage
metadata: {id: foo, displayName: Foo}
spec:
  module: stages.foo
  function: stages.foo
  placement: {slot: init}
  runner: {class: base}
  gate: {mode: opt_in, contexts: [snapshot]}
  api: {required: [stages.foo]}
YAML
    }
    BeforeEach 'setup_bad_gate'

    It "rejects opt_in mode without opt_in_flag"
      When call registry.validate_manifest "$BRIK_TEST_BADGATE/badgate.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should be present
    End
  End

  Describe "rejects manifest with unknown kind"
    setup_bad_kind() {
      BRIK_TEST_BADKIND=$(mktemp -d)
      cat > "$BRIK_TEST_BADKIND/badkind.yml" <<YAML
apiVersion: brik.dev/v1
kind: Pipeline
metadata: {id: foo, displayName: Foo}
spec: {}
YAML
    }
    BeforeEach 'setup_bad_kind'

    It "rejects kind != Stack|Stage"
      When call registry.validate_manifest "$BRIK_TEST_BADKIND/badkind.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown kind"
    End
  End

  Describe "rejects nonexistent file"
    It "returns BRIK_EXIT_INVALID_INPUT"
      When call registry.validate_manifest "/nonexistent/manifest.yml"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "manifest not found"
    End
  End
End
