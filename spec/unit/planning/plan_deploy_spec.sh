Describe "planning/plan.sh (deploy plan-kind)"
  Include "$BRIK_HOME/lib/planning/plan_writer.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  BeforeAll 'mock.infra.setup'
  AfterAll 'mock.infra.teardown'

  # A deploy plan parameterized by (version, environment). /tmp has no
  # brik.yml and no tags, so only the plan-kind logic is under test.
  deploy_plan() {
    plan_writer.write -- --workspace /tmp --mode safe \
      --type deploy --version v1.2.3 --environment staging
  }

  Describe "planType + deploy block"
    It "stamps planType=deploy"
      When call deploy_plan
      The status should be success
      The output should include '"planType": "deploy"'
    End

    It "stamps the deploy version and environment"
      block() {
        local out; out="$(deploy_plan)"
        printf '%s|%s' \
          "$(jq -r '.deploy.version' <<<"$out")" \
          "$(jq -r '.deploy.environment' <<<"$out")"
      }
      When call block
      The output should equal "v1.2.3|staging"
    End

    It "resolves context=release when a version is given"
      ctx() { deploy_plan | jq -r '.context'; }
      When call ctx
      The output should equal "release"
    End
  End

  Describe "stage subset (skip CI, run deploy/notify)"
    decision_of() {
      deploy_plan | jq -r --arg id "$1" '.stages[] | select(.id == $id) | .decision'
    }

    It "skips the build stage"
      When call decision_of build
      The output should equal "skip"
    End

    It "skips the test stage"
      When call decision_of test
      The output should equal "skip"
    End

    It "runs the deploy stage"
      When call decision_of deploy
      The output should equal "run"
    End

    It "runs the notify stage"
      When call decision_of notify
      The output should equal "run"
    End
  End

  Describe "gate reads the deploy plan"
    Include "$BRIK_HOME/lib/planning/plan_reader.sh"

    It "gates build as skip and deploy as run"
      gate_pair() {
        local plan; plan="$(mktemp)"
        deploy_plan > "$plan"
        local b="run" d="skip"
        pipeline.plan.should_run build "$plan"  || b="skip"
        pipeline.plan.should_run deploy "$plan" && d="run"
        rm -f "$plan"
        printf '%s|%s' "$b" "$d"
      }
      When call gate_pair
      The output should equal "skip|run"
    End
  End

  Describe "ci plan stays byte-compatible"
    It "omits planType in the default (ci) plan"
      ci_plantype() {
        plan_writer.write -- --workspace /tmp --mode safe | jq -r '.planType // "absent"'
      }
      When call ci_plantype
      The output should equal "absent"
    End

    It "remains reproducible for ci plans"
      a=$(plan_writer.write -- --workspace /tmp --mode safe)
      b=$(plan_writer.write -- --workspace /tmp --mode safe)
      When call test "$a" = "$b"
      The status should be success
    End
  End
End
