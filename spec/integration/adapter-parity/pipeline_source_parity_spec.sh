Describe "pipeline_source parity across adapters"
  # conditions.eval reads the 'pipeline_source' subject from BRIK_PIPELINE_SOURCE
  # (see lib/transverse/conditions.sh). For a deploy condition like
  # `pipeline_source == 'merge_request_event'` to behave identically on every
  # platform, each adapter MUST surface the SAME canonical token for the same
  # trigger. GitLab passes CI_PIPELINE_SOURCE through verbatim (already yields
  # 'merge_request_event' on MR pipelines); Jenkins has no native equivalent and
  # derives the token in jenkins-wrapper.sh.
  #
  # The canonical vocabulary is owned by the wrapper-context schema enum. This
  # spec is the drift detector ensuring the Jenkins adapter maps a merge/pull
  # request to that exact canonical token and never re-invents a synonym.

  JENKINS_WRAPPER="$BRIK_HOME/shared-libs/jenkins/scripts/jenkins-wrapper.sh"
  GITLAB_WRAPPER="$BRIK_HOME/shared-libs/gitlab/scripts/gitlab-wrapper.sh"
  CTX_SCHEMA="$BRIK_HOME/schemas/execution-environment/v1/wrapper-context.schema.json"

  Describe "canonical token"
    It "wrapper-context enum lists merge_request_event as the MR source"
      enum_has_mr() {
        jq -r '.properties.BRIK_PIPELINE_SOURCE.enum | index("merge_request_event") != null' "$CTX_SCHEMA"
      }
      When call enum_has_mr
      The output should equal "true"
    End
  End

  Describe "Jenkins adapter"
    It "maps a merge/pull request to the canonical merge_request_event token"
      # Jenkins Multibranch sets CHANGE_ID on PR builds; the wrapper must emit
      # the same token GitLab passes through, not 'push' nor a synonym.
      jenkins_mr_token() {
        grep -E 'BRIK_PIPELINE_SOURCE="merge_request_event"' "$JENKINS_WRAPPER" >/dev/null \
          && echo "ok" || echo "missing"
      }
      When call jenkins_mr_token
      The output should equal "ok"
    End

    It "guards the MR token behind CHANGE_ID (tag/branch push stays push)"
      # The merge_request_event assignment must be conditional on CHANGE_ID;
      # an unconditional assignment would mislabel every push as an MR.
      jenkins_guards_change_id() {
        awk '
          /if \[\[ -n "\$\{CHANGE_ID:-\}" \]\]; then/ { guard = 1 }
          guard && /BRIK_PIPELINE_SOURCE="merge_request_event"/ { found = 1 }
          guard && /^    fi/ { guard = 0 }
          END { print (found ? "guarded" : "unguarded") }
        ' "$JENKINS_WRAPPER"
      }
      When call jenkins_guards_change_id
      The output should equal "guarded"
    End
  End

  Describe "GitLab adapter"
    It "passes CI_PIPELINE_SOURCE through verbatim (native merge_request_event)"
      gitlab_passthrough() {
        grep -E 'BRIK_PIPELINE_SOURCE="\$\{CI_PIPELINE_SOURCE:-\}"' "$GITLAB_WRAPPER" >/dev/null \
          && echo "ok" || echo "missing"
      }
      When call gitlab_passthrough
      The output should equal "ok"
    End
  End
End
