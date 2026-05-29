Describe "cli/registry.sh - cli.registry internals"
  # In-process coverage for the `brik registry` command. The end-to-end
  # contract lives in registry_stages_spec.sh, but that invokes the CLI as a
  # subprocess, which kcov (attached to the ShellSpec bash) cannot see. These
  # When-call tests exercise cli.registry.* in-process so its coverage is
  # measured like the other CLI commands.
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/registry.sh"

  Describe "cli.registry.run"
    It "emits the per-stage list as JSON for 'stages --format json'"
      stages_json() { cli.registry.run stages --format json; }
      When call stages_json
      The status should eq 0
      The output should include '"id"'
      The output should include 'init'
    End

    It "prints usage and returns 2 when no subcommand is given"
      When call cli.registry.run
      The status should eq 2
      The output should include "usage: brik registry"
    End

    It "rejects an unknown subcommand"
      When call cli.registry.run bogus
      The status should eq 2
      The stderr should include "unknown registry subcommand: bogus"
    End

    It "rejects an unsupported --format"
      unsupported_fmt() { cli.registry.run stages --format yaml; }
      When call unsupported_fmt
      The status should eq 2
      The stderr should include "is not supported (only json)"
    End
  End
End
