Describe "artifact.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/artifact.sh"

  Describe "artifact.archive"
    It "returns 2 when no paths specified"
      When call artifact.archive --output /tmp/out.tar.gz
      The status should equal 2
      The stderr should include "no paths specified"
    End

    It "returns 2 when no output specified"
      When call artifact.archive somefile
      The status should equal 2
      The stderr should include "output path is required"
    End

    Describe "with temp workspace"
      setup_archive() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        printf 'hello\n' > "${TEST_WS}/src/file1.txt"
        printf 'world\n' > "${TEST_WS}/src/file2.txt"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_archive() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_archive'
      After 'cleanup_archive'

      It "returns 6 when source path does not exist"
        When call artifact.archive nonexistent --output out.tar.gz
        The status should equal 6
        The stderr should include "source path not found"
      End

      It "creates an archive from paths"
        invoke_archive() {
          artifact.archive src --output out.tar.gz 2>/dev/null || return 1
          [[ -f out.tar.gz ]]
        }
        When call invoke_archive
        The status should be success
      End

      It "creates an archive with multiple paths"
        invoke_multi() {
          artifact.archive src/file1.txt src/file2.txt --output multi.tar.gz 2>/dev/null || return 1
          [[ -f multi.tar.gz ]]
        }
        When call invoke_multi
        The status should be success
      End

      It "logs archive creation"
        When call artifact.archive src --output out.tar.gz
        The status should be success
        The stderr should include "archive created"
      End
    End
  End

  Describe "artifact.extract"
    It "returns 2 when no archive specified"
      When call artifact.extract --output /tmp/dest
      The status should equal 2
      The stderr should include "archive path is required"
    End

    It "returns 2 when no output specified"
      When call artifact.extract /tmp/test.tar.gz
      The status should equal 2
      The stderr should include "output destination is required"
    End

    Describe "with temp archive"
      setup_extract() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/src"
        printf 'content\n' > "${TEST_WS}/src/data.txt"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
        tar -czf archive.tar.gz src 2>/dev/null
      }
      cleanup_extract() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_extract'
      After 'cleanup_extract'

      It "returns 6 when archive does not exist"
        When call artifact.extract missing.tar.gz --output dest
        The status should equal 6
        The stderr should include "archive not found"
      End

      It "extracts archive to destination"
        invoke_extract() {
          artifact.extract archive.tar.gz --output dest 2>/dev/null || return 1
          [[ -f dest/src/data.txt ]]
        }
        When call invoke_extract
        The status should be success
      End

      It "logs extraction"
        When call artifact.extract archive.tar.gz --output dest2
        The status should be success
        The stderr should include "extraction complete"
      End
    End
  End
End
