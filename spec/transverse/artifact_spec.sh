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

    It "returns non-zero on an unsupported path type (fifo)"
      run_fifo() {
        mkfifo "$ART_WS/pipe"
        artifact.summarize "$ART_WS/pipe" 2>/dev/null
      }
      When call run_fifo
      The status should not equal 0
    End

    It "returns BRIK_EXIT_MISSING_DEP when jq is unavailable"
      run_no_jq() {
        command() {
          [[ "$1" == "-v" && "$2" == "jq" ]] && return 1
          builtin command "$@"
        }
        printf 'data' > "$ART_WS/x.tgz"
        artifact.summarize "$ART_WS/x.tgz"
      }
      When call run_no_jq
      The status should equal 3
      The stderr should include "jq is required"
    End
  End

  Describe "artifact.summarize stack-aware main file detection"
    It "picks the .jar for a java directory"
      run_java() {
        mkdir -p "$ART_WS/target"
        printf 'JARDATA' > "$ART_WS/target/app.jar"
        printf 'noise' > "$ART_WS/target/pom.xml"
        artifact.summarize "$ART_WS/target" java | jq -r '.main_file'
      }
      When call run_java
      The output should equal "app.jar"
    End

    It "reports size_bytes of the main file, not the directory total"
      run_java_size() {
        mkdir -p "$ART_WS/target"
        printf '1234567' > "$ART_WS/target/app.jar"
        printf 'aaaaaaaaaaaaaaaaaaaa' > "$ART_WS/target/extra.txt"
        artifact.summarize "$ART_WS/target" java | jq -r '.size_bytes'
      }
      When call run_java_size
      The output should equal "7"
    End

    It "picks the .whl for a python directory"
      run_python() {
        mkdir -p "$ART_WS/dist"
        printf 'WHEEL' > "$ART_WS/dist/pkg-1.0.whl"
        artifact.summarize "$ART_WS/dist" python | jq -r '.main_file'
      }
      When call run_python
      The output should equal "pkg-1.0.whl"
    End

    It "picks the .tgz for a node directory"
      run_node() {
        mkdir -p "$ART_WS/out"
        printf 'TGZ' > "$ART_WS/out/bundle.tgz"
        artifact.summarize "$ART_WS/out" node | jq -r '.main_file'
      }
      When call run_node
      The output should equal "bundle.tgz"
    End

    It "picks the .nupkg for a dotnet directory"
      run_dotnet() {
        mkdir -p "$ART_WS/bin"
        printf 'NUPKG' > "$ART_WS/bin/lib.nupkg"
        artifact.summarize "$ART_WS/bin" dotnet | jq -r '.main_file'
      }
      When call run_dotnet
      The output should equal "lib.nupkg"
    End

    It "prefers the project-name-prefixed artifact when several match"
      run_proj_match() {
        mkdir -p "$ART_WS/dist"
        printf 'DEP' > "$ART_WS/dist/pytest-7.0.whl"
        printf 'MAIN' > "$ART_WS/dist/my_app-1.0.whl"
        BRIK_PROJECT_NAME="my-app" artifact.summarize "$ART_WS/dist" python | jq -r '.main_file'
      }
      When call run_proj_match
      The output should equal "my_app-1.0.whl"
    End

    It "falls back to the largest binary for a rust directory"
      run_rust() {
        mkdir -p "$ART_WS/release"
        printf 'tiny' > "$ART_WS/release/small"
        printf 'a much larger binary blob here' > "$ART_WS/release/mybin"
        artifact.summarize "$ART_WS/release" rust | jq -r '.main_file'
      }
      When call run_rust
      The output should equal "mybin"
    End

    It "treats a single non-empty file in a directory as the main artifact"
      run_single() {
        mkdir -p "$ART_WS/onefile"
        printf 'bundled output' > "$ART_WS/onefile/index.js"
        artifact.summarize "$ART_WS/onefile" auto | jq -r '.main_file'
      }
      When call run_single
      The output should equal "index.js"
    End

    It "produces a non-blank sha256 for an empty directory"
      run_empty_dir() {
        mkdir -p "$ART_WS/empty"
        artifact.summarize "$ART_WS/empty" | jq -r '.sha256'
      }
      When call run_empty_dir
      The output should not be blank
    End
  End

  Describe "_artifact._size_bytes"
    It "prints 0 for a path that is neither a file nor a directory"
      When call _artifact._size_bytes "$ART_WS/no-such-path"
      The output should equal "0"
    End
  End
End
