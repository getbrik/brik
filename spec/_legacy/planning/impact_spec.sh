Describe "planning/impact.sh"
  Include "$BRIK_HOME/lib/planning/impact.sh"

  Describe "impact.match_one"
    It "matches a single segment"
      When call impact.match_one "src/foo.js" "src/*.js"
      The status should be success
    End

    It "matches across directories with globstar"
      When call impact.match_one "src/sub/dir/foo.js" "**/*.js"
      The status should be success
    End

    It "rejects a non-matching extension"
      When call impact.match_one "src/foo.py" "**/*.js"
      The status should equal 1
    End

    It "rejects an empty pattern"
      When call impact.match_one "src/foo.js" ""
      The status should equal 1
    End
  End

  Describe "impact.match_any"
    It "returns true if any pattern matches"
      When call impact.match_any "Cargo.toml" "**/*.rs" "Cargo.toml"
      The status should be success
    End

    It "returns false when no pattern matches"
      When call impact.match_any "src/main.go" "**/*.js" "**/*.ts"
      The status should equal 1
    End
  End

  Describe "impact.stage_patterns"
    It "returns own changes when declared on the stage"
      When call impact.stage_patterns init
      The status should be success
      The output should include "brik.yml"
    End

    It "falls back to stack impact when use_stack_impact is set"
      When call impact.stage_patterns lint node
      The status should be success
      The output should include "**/*.ts"
    End
  End

  Describe "impact.stage_is_impacted (changes file)"
    It "reports impact when a changed file matches"
      tmp=$(mktemp)
      printf 'src/index.ts\0README.md\0' > "$tmp"
      When call impact.stage_is_impacted lint node "$tmp"
      The status should be success
      rm -f "$tmp"
    End

    It "reports no impact when no changed file matches"
      tmp=$(mktemp)
      printf 'README.md\0docs/foo.md\0' > "$tmp"
      When call impact.stage_is_impacted lint node "$tmp"
      The status should equal 1
      rm -f "$tmp"
    End

    It "treats empty changes file as cold start (run)"
      tmp=$(mktemp)
      When call impact.stage_is_impacted lint node "$tmp"
      The status should be success
      rm -f "$tmp"
    End

    It "treats missing changes file as cold start"
      When call impact.stage_is_impacted lint node "/nonexistent"
      The status should be success
    End
  End

  Describe "impact.stage_matched_globs"
    It "lists each pattern that matched at least one file"
      tmp=$(mktemp)
      printf 'src/index.ts\0README.md\0' > "$tmp"
      When call impact.stage_matched_globs lint node "$tmp"
      The status should be success
      The output should include "**/*.ts"
      rm -f "$tmp"
    End

    It "returns empty when no file matched"
      tmp=$(mktemp)
      printf 'docs/manual.adoc\0' > "$tmp"
      When call impact.stage_matched_globs lint node "$tmp"
      The status should be success
      The output should equal ""
      rm -f "$tmp"
    End
  End
End
