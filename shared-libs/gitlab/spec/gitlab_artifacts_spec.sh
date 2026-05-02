Describe "shared-libs/gitlab templates - brik-artifacts paths"
  TEMPLATES_DIR="${BRIK_HOME}/shared-libs/gitlab/templates/jobs"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  artifact_has_brik_artifacts() {
    local file="$1" job_key="$2"
    yq -e ".${job_key}.artifacts.paths | contains([\"brik-artifacts/\"])" \
      "$file" >/dev/null 2>&1
  }

  artifact_when_always() {
    local file="$1" job_key="$2"
    [[ "$(yq -r ".${job_key}.artifacts.when" "$file")" == "always" ]]
  }

  artifact_expire_in() {
    local file="$1" job_key="$2"
    yq -r ".${job_key}.artifacts.expire_in" "$file"
  }

  # Stage jobs: brik-artifacts/ in paths, when=always, expire_in 1 week.
  Describe "stage jobs declare brik-artifacts/ as an artifact path"
    Parameters
      "init"           "brik-init"
      "release"        "brik-release"
      "build"          "brik-build"
      "lint"           "brik-lint"
      "sast"           "brik-sast"
      "scan"           "brik-scan"
      "test"           "brik-test"
      "package"        "brik-package"
      "container-scan" "brik-container-scan"
      "deploy"         "brik-deploy"
    End

    It "$1.yml lists brik-artifacts/ under .$2.artifacts.paths"
      Skip if "yq not installed" yq_missing
      When call artifact_has_brik_artifacts "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End

    It "$1.yml uses artifacts.when: always"
      Skip if "yq not installed" yq_missing
      When call artifact_when_always "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End

    It "$1.yml uses artifacts.expire_in: 1 week"
      Skip if "yq not installed" yq_missing
      When call artifact_expire_in "${TEMPLATES_DIR}/$1.yml" "$2"
      The output should equal "1 week"
    End
  End

  Describe "notify job (longer retention for the proof artefact)"
    It "notify.yml lists brik-artifacts/ under .brik-notify.artifacts.paths"
      Skip if "yq not installed" yq_missing
      When call artifact_has_brik_artifacts "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The status should be success
    End

    It "notify.yml uses artifacts.when: always"
      Skip if "yq not installed" yq_missing
      When call artifact_when_always "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The status should be success
    End

    It "notify.yml uses artifacts.expire_in: 1 month (longer retention for proof)"
      Skip if "yq not installed" yq_missing
      When call artifact_expire_in "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The output should equal "1 month"
    End
  End
End
