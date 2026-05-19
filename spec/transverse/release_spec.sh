Describe "transverse/release.sh (Phase 9.A)"
  Include "$BRIK_HOME/lib/transverse/release.sh"

  setup_release() {
    REL_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE="$REL_DIR"
    export BRIK_CONFIG_FILE="$REL_DIR/brik.yml"
    unset BRIK_COMMIT_TAG
  }
  cleanup_release() {
    rm -rf "$REL_DIR"
    unset BRIK_WORKSPACE BRIK_CONFIG_FILE BRIK_COMMIT_TAG
  }
  Before 'setup_release'
  After 'cleanup_release'

  Describe "release.compute_profile"
    It "returns 'none' when brik.yml does not declare a profile"
      printf 'version: 1\nproject:\n  name: t\n' > "$BRIK_CONFIG_FILE"
      When call release.compute_profile
      The output should equal "none"
    End

    It "returns the configured profile when present"
      printf 'version: 1\nproject:\n  name: t\nrelease:\n  profile: trunk-based\n' \
        > "$BRIK_CONFIG_FILE"
      When call release.compute_profile
      The output should equal "trunk-based"
    End

    It "returns 'none' when brik.yml is missing"
      rm -f "$BRIK_CONFIG_FILE"
      When call release.compute_profile
      The output should equal "none"
    End

    It "returns 'none' when the value is null"
      printf 'version: 1\nproject:\n  name: t\nrelease:\n  profile: null\n' \
        > "$BRIK_CONFIG_FILE"
      When call release.compute_profile
      The output should equal "none"
    End
  End

  Describe "release.compute_version"
    It "falls back to 0.0.0 when no git tag exists"
      git -C "$REL_DIR" init -q
      git -C "$REL_DIR" config user.email "t@t"
      git -C "$REL_DIR" config user.name  "t"
      : > "$REL_DIR/file"
      git -C "$REL_DIR" add -A >/dev/null
      git -C "$REL_DIR" commit -q -m "baseline"
      When call release.compute_version
      The output should equal "0.0.0"
    End

    It "returns the latest tag with the default 'v' prefix stripped"
      git -C "$REL_DIR" init -q
      git -C "$REL_DIR" config user.email "t@t"
      git -C "$REL_DIR" config user.name  "t"
      : > "$REL_DIR/file"
      git -C "$REL_DIR" add -A >/dev/null
      git -C "$REL_DIR" commit -q -m "baseline"
      git -C "$REL_DIR" tag v1.2.3
      When call release.compute_version
      The output should equal "1.2.3"
    End

    It "honors a custom .release.tag_prefix"
      printf 'version: 1\nproject:\n  name: t\nrelease:\n  tag_prefix: "rel-"\n' \
        > "$BRIK_CONFIG_FILE"
      git -C "$REL_DIR" init -q
      git -C "$REL_DIR" config user.email "t@t"
      git -C "$REL_DIR" config user.name  "t"
      : > "$REL_DIR/file"
      git -C "$REL_DIR" add -A >/dev/null
      git -C "$REL_DIR" commit -q -m "baseline"
      git -C "$REL_DIR" tag rel-4.5.6
      When call release.compute_version
      The output should equal "4.5.6"
    End

    It "returns 0.0.0 when the workspace is not a git repo"
      When call release.compute_version
      The output should equal "0.0.0"
    End
  End

  Describe "release.compute_is_candidate"
    It "returns 0 when BRIK_COMMIT_TAG is unset"
      When call release.compute_is_candidate
      The output should equal "0"
    End

    It "returns 1 when BRIK_COMMIT_TAG is set"
      export BRIK_COMMIT_TAG="v1.2.3"
      When call release.compute_is_candidate
      The output should equal "1"
    End

    It "returns 0 when BRIK_COMMIT_TAG is empty"
      export BRIK_COMMIT_TAG=""
      When call release.compute_is_candidate
      The output should equal "0"
    End
  End
End
