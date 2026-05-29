# L2 edge: Registry -> Planning (graph edge #11)
#
# A stage manifest declares its opt-in gate flag (spec.gate.opt_in_flag). The
# registry loads it and the planning notion must consume exactly that flag
# when deciding run/skip. This spec exercises the real registry accessor and
# the real planner together (neither stubbed), proving the manifest gate field
# wires through to the plan decision. Schema validation of manifests is an L0
# contract concern and intentionally not duplicated here.

Describe "L2 registry -> planning: gate.opt_in_flag is consumed by the planner"
  Include "$BRIK_HOME/lib/registry/registry.sh"
  Include "$BRIK_HOME/lib/planning/impact.sh"
  Include "$BRIK_HOME/lib/planning/plan.sh"

  decision() { plan.decide "$@" | cut -f1; }

  Describe "the registry exposes each opt-in stage's declared flag"
    Parameters
      "deploy"  "--with-deploy"
      "package" "--with-package"
      "release" "--with-release"
    End

    It "stage $1 declares opt_in_flag $2"
      When call registry.stage.gate_opt_in_flag "$1"
      The output should equal "$2"
    End
  End

  Describe "the planner honors the flag declared in the manifest"
    It "skips deploy when --with-deploy is not set"
      When call decision deploy safe snapshot false false false "" /dev/null
      The output should equal "skip"
    End

    It "runs deploy when --with-deploy is set"
      When call decision deploy safe snapshot false false true "" /dev/null
      The output should equal "run"
    End

    It "skips package when --with-package is not set"
      When call decision package safe snapshot false false false "" /dev/null
      The output should equal "skip"
    End

    It "runs package when --with-package is set"
      When call decision package safe snapshot false true false "" /dev/null
      The output should equal "run"
    End
  End
End
