Describe "stacks.cache_paths"
  Include "$BRIK_HOME/lib/stacks/_deps.sh"

  # Canonical list of stack-specific cache paths -- single source of truth
  # consumed by CI cache restoration (GitLab templates), Jenkins cleanWs
  # excludes, and _brik_gitlab._ensure_artefact_markers. Order matters: it
  # is the order the GitLab job templates and the marker function iterate.
  expected_paths() {
    cat <<'EOF'
.npm
.cache/pip
.m2/repository
.gradle/caches
.gradle/wrapper
.cargo/registry
.cargo/git
.nuget/packages
EOF
  }

  It "is defined as a function"
    callable_check() { declare -f stacks.cache_paths >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "emits the canonical list, one path per line, in stable order"
    When call stacks.cache_paths
    The output should equal "$(expected_paths)"
  End

  It "produces identical output across consecutive invocations"
    diff_runs() {
      local first second
      first="$(stacks.cache_paths)"
      second="$(stacks.cache_paths)"
      [[ "$first" == "$second" ]]
    }
    When call diff_runs
    The status should be success
  End

  It "covers every supported stack with at least one cache path"
    has_stack_paths() {
      local out
      out="$(stacks.cache_paths)"
      # node, python, maven, gradle, cargo, nuget = 6 ecosystems
      grep -q '^\.npm$'             <<<"$out" || return 1
      grep -q '^\.cache/pip$'       <<<"$out" || return 1
      grep -q '^\.m2/repository$'   <<<"$out" || return 1
      grep -q '^\.gradle/caches$'   <<<"$out" || return 1
      grep -q '^\.cargo/registry$'  <<<"$out" || return 1
      grep -q '^\.nuget/packages$'  <<<"$out" || return 1
    }
    When call has_stack_paths
    The status should be success
  End
End
