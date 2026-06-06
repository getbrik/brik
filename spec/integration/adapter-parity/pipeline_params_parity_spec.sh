Describe "pipeline params: SoT <-> GitLab/Jenkins parity"
  # lib/registry/pipeline-params.yml is the single source of truth for
  # user-facing pipeline parameters. This spec is the blocking gate that keeps
  # the GitLab and Jenkins surfaces aligned with it (plan section 2.2):
  #   - every SoT param is exposed on the surface(s) its `parity` declares;
  #   - no surface exposes a BRIK_* parameter absent from the SoT.

  SOT="$BRIK_HOME/lib/registry/pipeline-params.yml"
  GITLAB="$BRIK_HOME/shared-libs/gitlab/templates/pipeline.yml"
  JENKINS="$BRIK_HOME/shared-libs/jenkins/vars/brikPipeline.groovy"

  gitlab_has_param() { yq -e ".variables.\"$1\"" "$GITLAB" >/dev/null 2>&1; }
  jenkins_has_param() { grep -q "name: '$1'" "$JENKINS"; }

  Describe "the SoT manifest is well-formed"
    It "is valid YAML with at least one named param"
      count_params() { yq -r '.params | length' "$SOT"; }
      When call count_params
      The output should not equal "0"
      The status should be success
    End

    It "declares the two CD params with scope cd and parity both"
      cd_params() {
        yq -r '.params[] | select(.name | test("^BRIK_DEPLOY_(VERSION|ENVIRONMENT)$")) | .name + ":" + .scope + ":" + .parity' "$SOT" | sort | tr '\n' ' '
      }
      When call cd_params
      The output should equal "BRIK_DEPLOY_ENVIRONMENT:cd:both BRIK_DEPLOY_VERSION:cd:both "
    End
  End

  Describe "every SoT param is exposed on its declared surface"
    It "is present on the GitLab surface (parity both|gitlab-only)"
      check_gitlab() {
        local missing="" name parity
        while read -r name parity; do
          case "$parity" in
            both|gitlab-only) gitlab_has_param "$name" || missing="$missing $name" ;;
          esac
        done < <(yq -r '.params[] | .name + " " + .parity' "$SOT")
        [[ -z "$missing" ]] || { echo "missing on GitLab:$missing" >&2; return 1; }
      }
      When call check_gitlab
      The status should be success
    End

    It "is present on the Jenkins surface (parity both|jenkins-only)"
      check_jenkins() {
        local missing="" name parity
        while read -r name parity; do
          case "$parity" in
            both|jenkins-only) jenkins_has_param "$name" || missing="$missing $name" ;;
          esac
        done < <(yq -r '.params[] | .name + " " + .parity' "$SOT")
        [[ -z "$missing" ]] || { echo "missing on Jenkins:$missing" >&2; return 1; }
      }
      When call check_jenkins
      The status should be success
    End
  End

  Describe "no surface exposes an undeclared parameter"
    It "every Jenkins BRIK_* parameter is declared in the SoT"
      check_jenkins_reverse() {
        local undeclared="" name
        while read -r name; do
          yq -e ".params[] | select(.name == \"$name\")" "$SOT" >/dev/null 2>&1 \
            || undeclared="$undeclared $name"
        done < <(grep -oE "name: '(BRIK_[A-Z_]+)'" "$JENKINS" | sed "s/name: '//; s/'//")
        [[ -z "$undeclared" ]] || { echo "undeclared in SoT:$undeclared" >&2; return 1; }
      }
      When call check_jenkins_reverse
      The status should be success
    End
  End
End
