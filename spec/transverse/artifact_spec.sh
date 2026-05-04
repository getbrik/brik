Describe "transverse/artifact.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/artifact.sh"

  setup_workspace() {
    ART_WS="$(mktemp -d)"
  }
  cleanup_workspace() {
    rm -rf "$ART_WS"
  }
  Before 'setup_workspace'
  After 'cleanup_workspace'

  Describe "artifact.summarize on a single file"
    It "produces a JSON object with type=file"
      run_summarize_file() {
        printf 'hello world\n' > "$ART_WS/build.tgz"
        artifact.summarize "$ART_WS/build.tgz" | jq -r '.type'
      }
      When call run_summarize_file
      The output should equal "file"
    End

    It "produces name as the file basename"
      run_summarize_name() {
        printf 'hello world\n' > "$ART_WS/build.tgz"
        artifact.summarize "$ART_WS/build.tgz" | jq -r '.name'
      }
      When call run_summarize_name
      The output should equal "build.tgz"
    End

    It "produces size_bytes as a JSON integer"
      run_summarize_size() {
        printf 'hello world\n' > "$ART_WS/build.tgz"
        artifact.summarize "$ART_WS/build.tgz" | jq -r '.size_bytes'
      }
      When call run_summarize_size
      The output should equal "12"
    End

    It "produces sha256 matching sha256sum"
      run_summarize_sha() {
        printf 'hello world\n' > "$ART_WS/build.tgz"
        local expected
        expected="$(sha256sum "$ART_WS/build.tgz" 2>/dev/null | cut -d' ' -f1)"
        local got
        got="$(artifact.summarize "$ART_WS/build.tgz" | jq -r '.sha256')"
        [[ "$got" == "$expected" ]] && echo "match" || echo "mismatch:$got|$expected"
      }
      When call run_summarize_sha
      The output should equal "match"
    End

    It "produces path as the absolute path"
      run_summarize_path() {
        printf 'x\n' > "$ART_WS/file.bin"
        artifact.summarize "$ART_WS/file.bin" | jq -r '.path'
      }
      When call run_summarize_path
      The output should end with "/file.bin"
    End
  End

  Describe "artifact.summarize on a directory"
    It "produces type=directory"
      run_summarize_dir_type() {
        mkdir -p "$ART_WS/dist"
        printf 'a\n' > "$ART_WS/dist/main.js"
        printf 'b\n' > "$ART_WS/dist/index.html"
        artifact.summarize "$ART_WS/dist" | jq -r '.type'
      }
      When call run_summarize_dir_type
      The output should equal "directory"
    End

    It "produces sha256 deterministic across two equivalent dirs"
      run_summarize_dir_sha_deterministic() {
        mkdir -p "$ART_WS/d1" "$ART_WS/d2"
        printf 'a\n' > "$ART_WS/d1/main.js"
        printf 'b\n' > "$ART_WS/d1/index.html"
        printf 'a\n' > "$ART_WS/d2/main.js"
        printf 'b\n' > "$ART_WS/d2/index.html"
        local h1 h2
        h1="$(artifact.summarize "$ART_WS/d1" | jq -r '.sha256')"
        h2="$(artifact.summarize "$ART_WS/d2" | jq -r '.sha256')"
        [[ -n "$h1" && "$h1" == "$h2" ]] && echo "deterministic" || echo "drift:$h1|$h2"
      }
      When call run_summarize_dir_sha_deterministic
      The output should equal "deterministic"
    End

    It "size_bytes is the cumulative size of the directory contents"
      run_summarize_dir_size() {
        mkdir -p "$ART_WS/d3"
        printf 'a\n' > "$ART_WS/d3/x"
        printf 'b\n' > "$ART_WS/d3/y"
        artifact.summarize "$ART_WS/d3" | jq -r '.size_bytes'
      }
      When call run_summarize_dir_size
      The output should equal "4"
    End
  End

  Describe "artifact.summarize error handling"
    It "returns non-zero on a missing path"
      run_missing() {
        artifact.summarize "$ART_WS/does-not-exist" 2>/dev/null
      }
      When call run_missing
      The status should not equal 0
    End

    It "returns non-zero when called without arguments"
      When call artifact.summarize
      The status should not equal 0
      The stderr should not be blank
    End
  End
End
