Describe "cache paths parity across consumers"
  # stacks.cache_paths is the single source of truth (see lib/stacks/_deps.sh).
  # Three downstream consumers must stay in sync with it:
  #   1. GitLab job templates declare cache.paths inline (kept verbatim to
  #      keep the YAML readable -- GitLab cannot source bash at template parse).
  #   2. Jenkins brikIntegrate.groovy maps each path to a "<top-level>/**"
  #      EXCLUDE pattern for cleanWs.
  #   3. shared-libs/gitlab/scripts/gitlab-wrapper.sh (after P2) pre-creates
  #      a .brik-keep marker under each path. The marker function reads
  #      stacks.cache_paths directly, so the parity check there is implicit.
  #
  # This spec is the drift detector for the two non-source-reading consumers.
  Include "$BRIK_HOME/lib/stacks/_deps.sh"

  canonical_paths() {
    stacks.cache_paths
  }

  # Strip GitLab's optional trailing slash so '.npm' and '.npm/' compare equal.
  normalize_paths() {
    sed -e 's|/$||'
  }

  extract_gitlab_paths() {
    local yml="$1"
    awk '
      /^  cache:/ { in_cache = 1; next }
      in_cache && /^    paths:/ { in_paths = 1; next }
      in_paths && /^      - / { sub(/^      - /, ""); print; next }
      in_paths && !/^      - / { in_paths = 0; in_cache = 0 }
    ' "$yml"
  }

  # Extract the cleanWs EXCLUDE patterns from brikIntegrate.groovy and emit
  # the bare top-level directory for each. The result is the set of
  # top-level dirs Jenkins protects across cleanWs cycles.
  extract_jenkins_dirs() {
    local groovy="$1"
    grep -E "^\s*\[pattern: '[^']+/\*\*', type: 'EXCLUDE'\]" "$groovy" \
      | sed -E "s|.*\[pattern: '([^/]+)/\*\*'.*|\1|"
  }

  Describe "GitLab job templates"
    Parameters
      "build.yml"
      "lint.yml"
      "package.yml"
      "sast.yml"
      "scan.yml"
      "test.yml"
    End

    It "$1 declares cache.paths matching stacks.cache_paths"
      check_yml() {
        local yml="$BRIK_HOME/shared-libs/gitlab/templates/jobs/$1"
        local declared canonical
        declared="$(extract_gitlab_paths "$yml" | normalize_paths)"
        canonical="$(canonical_paths | normalize_paths)"
        if [[ "$declared" == "$canonical" ]]; then
          echo "ok"
        else
          {
            echo "drift in $1"
            echo "--- declared ---"
            echo "$declared"
            echo "--- canonical ---"
            echo "$canonical"
          } >&2
          echo "drift"
        fi
      }
      When call check_yml "$1"
      The output should equal "ok"
    End
  End

  Describe "Jenkins brikIntegrate cleanWs excludes"
    It "covers every top-level dir from stacks.cache_paths"
      check_jenkins() {
        local groovy="$BRIK_HOME/shared-libs/jenkins/vars/brikIntegrate.groovy"
        local jenkins_dirs canonical_top
        jenkins_dirs="$(extract_jenkins_dirs "$groovy" | sort -u)"
        canonical_top="$(canonical_paths | normalize_paths | cut -d/ -f1 | sort -u)"
        local missing
        missing="$(comm -23 <(echo "$canonical_top") <(echo "$jenkins_dirs"))"
        if [[ -z "$missing" ]]; then
          echo "ok"
        else
          {
            echo "Jenkins cleanWs missing exclude patterns for:"
            echo "$missing"
            echo "--- declared excludes ---"
            echo "$jenkins_dirs"
          } >&2
          echo "missing"
        fi
      }
      When call check_jenkins
      The output should equal "ok"
    End
  End
End
