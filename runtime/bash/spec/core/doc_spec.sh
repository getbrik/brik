Describe "doc.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/doc.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "doc.generate"
    It "returns 2 for unknown option"
      When call doc.generate --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for unsupported tool"
      When call doc.generate --tool unsupported
      The status should equal 2
      The stderr should include "unsupported documentation tool"
    End

    Describe "no tool detected"
      setup_empty() {
        TEST_WS="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_empty() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 7 when no tool detected and none specified"
        When call doc.generate
        The status should equal 7
        The stderr should include "no documentation tool detected"
      End
    End

    Describe "auto-detection"
      Describe "mkdocs"
        setup_mkdocs_detect() {
          TEST_WS="$(mktemp -d)"
          printf 'site_name: test\n' > "${TEST_WS}/mkdocs.yml"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_mkdocs_detect() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_mkdocs_detect'
        After 'cleanup_mkdocs_detect'

        It "detects mkdocs from mkdocs.yml"
          invoke_detect() {
            _doc._detect_tool
          }
          When call invoke_detect
          The output should equal "mkdocs"
        End
      End

      Describe "sphinx"
        setup_sphinx_detect() {
          TEST_WS="$(mktemp -d)"
          mkdir -p "${TEST_WS}/docs"
          printf 'project = "test"\n' > "${TEST_WS}/docs/conf.py"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_sphinx_detect() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_sphinx_detect'
        After 'cleanup_sphinx_detect'

        It "detects sphinx from docs/conf.py"
          invoke_detect() {
            _doc._detect_tool
          }
          When call invoke_detect
          The output should equal "sphinx"
        End
      End

      Describe "javadoc"
        setup_javadoc_detect() {
          TEST_WS="$(mktemp -d)"
          printf '<project/>\n' > "${TEST_WS}/pom.xml"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_javadoc_detect() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_javadoc_detect'
        After 'cleanup_javadoc_detect'

        It "detects javadoc from pom.xml"
          invoke_detect() {
            _doc._detect_tool
          }
          When call invoke_detect
          The output should equal "javadoc"
        End
      End

      Describe "rustdoc"
        setup_rustdoc_detect() {
          TEST_WS="$(mktemp -d)"
          printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_rustdoc_detect() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_rustdoc_detect'
        After 'cleanup_rustdoc_detect'

        It "detects rustdoc from Cargo.toml"
          invoke_detect() {
            _doc._detect_tool
          }
          When call invoke_detect
          The output should equal "rustdoc"
        End
      End
    End

    Describe "dry-run with mock tools"
      setup_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        for tool in mkdocs sphinx-build mvn gradle cargo; do
          mock.create_exit "$tool" 0
        done
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_dryrun() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DOC_TOOL BRIK_DOC_OUTPUT BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "dry-runs mkdocs"
        When call doc.generate --tool mkdocs --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs mkdocs with output"
        When call doc.generate --tool mkdocs --output site --dry-run
        The status should be success
        The stderr should include "[dry-run]"
        The stderr should include "site"
      End

      It "dry-runs sphinx"
        When call doc.generate --tool sphinx --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs sphinx with conf.py in root"
        invoke_sphinx_root() {
          printf 'project = "test"\n' > conf.py
          doc.generate --tool sphinx --dry-run
        }
        When call invoke_sphinx_root
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs javadoc with pom.xml"
        invoke_javadoc_dry() {
          printf '<project/>\n' > pom.xml
          doc.generate --tool javadoc --dry-run
        }
        When call invoke_javadoc_dry
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs javadoc with pom.xml and output"
        invoke_javadoc_out() {
          printf '<project/>\n' > pom.xml
          doc.generate --tool javadoc --output docs-out --dry-run
        }
        When call invoke_javadoc_out
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs javadoc with build.gradle"
        invoke_javadoc_gradle() {
          rm -f pom.xml
          printf 'apply plugin: java\n' > build.gradle
          doc.generate --tool javadoc --dry-run
        }
        When call invoke_javadoc_gradle
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "returns 7 for javadoc without build files"
        invoke_javadoc_nobuild() {
          rm -f pom.xml build.gradle build.gradle.kts
          doc.generate --tool javadoc
        }
        When call invoke_javadoc_nobuild
        The status should equal 7
        The stderr should include "no pom.xml or build.gradle"
      End

      It "dry-runs rustdoc"
        When call doc.generate --tool rustdoc --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "dry-runs rustdoc with output"
        When call doc.generate --tool rustdoc --output target-docs --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "actual execution with mock tools"
      setup_exec() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        for tool in mkdocs sphinx-build mvn gradle cargo; do
          mock.create_logging "$tool" "$MOCK_LOG"
        done
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_exec() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_exec'
      After 'cleanup_exec'

      It "runs mkdocs build"
        invoke_mkdocs_run() {
          doc.generate --tool mkdocs 2>/dev/null || return 1
          grep -q "mkdocs build" "$MOCK_LOG"
        }
        When call invoke_mkdocs_run
        The status should be success
      End

      It "runs sphinx-build"
        invoke_sphinx_run() {
          doc.generate --tool sphinx 2>/dev/null || return 1
          grep -q "sphinx-build" "$MOCK_LOG"
        }
        When call invoke_sphinx_run
        The status should be success
      End

      It "runs cargo doc"
        invoke_cargo_run() {
          doc.generate --tool rustdoc 2>/dev/null || return 1
          grep -q "cargo doc" "$MOCK_LOG"
        }
        When call invoke_cargo_run
        The status should be success
      End

      It "runs mvn javadoc"
        invoke_mvn_run() {
          printf '<project/>\n' > pom.xml
          doc.generate --tool javadoc 2>/dev/null || return 1
          grep -q "mvn -B javadoc" "$MOCK_LOG"
        }
        When call invoke_mvn_run
        The status should be success
      End

      It "auto-detects and runs mkdocs"
        invoke_auto_mkdocs() {
          printf 'site_name: test\n' > mkdocs.yml
          doc.generate 2>/dev/null || return 1
          grep -q "mkdocs" "$MOCK_LOG"
        }
        When call invoke_auto_mkdocs
        The status should be success
      End
    End

    Describe "auto-detection edge cases"
      Describe "mkdocs.yaml variant"
        setup_yaml() {
          TEST_WS="$(mktemp -d)"
          printf 'site_name: test\n' > "${TEST_WS}/mkdocs.yaml"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_yaml() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_yaml'
        After 'cleanup_yaml'

        It "detects mkdocs from mkdocs.yaml"
          When call _doc._detect_tool
          The output should equal "mkdocs"
        End
      End

      Describe "build.gradle.kts"
        setup_kts() {
          TEST_WS="$(mktemp -d)"
          printf 'plugins { java }\n' > "${TEST_WS}/build.gradle.kts"
          ORIG_DIR="$(pwd)"
          cd "$TEST_WS" || return 1
        }
        cleanup_kts() {
          cd "$ORIG_DIR" || true
          rm -rf "$TEST_WS"
        }
        Before 'setup_kts'
        After 'cleanup_kts'

        It "detects javadoc from build.gradle.kts"
          When call _doc._detect_tool
          The output should equal "javadoc"
        End
      End
    End
  End
End
