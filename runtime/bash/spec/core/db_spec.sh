Describe "db.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/db.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "db.migrate"
    It "returns 2 when no tool specified"
      When call db.migrate --url "jdbc:postgresql://localhost/test"
      The status should equal 2
      The stderr should include "migration tool is required"
    End

    It "returns 2 for unknown option"
      When call db.migrate --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for unsupported tool"
      When call db.migrate --tool unsupported
      The status should equal 2
      The stderr should include "unsupported migration tool"
    End

    Describe "with mock flyway"
      setup_flyway() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_flyway.log"
        mock.create_logging "flyway" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_flyway() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_flyway'
      After 'cleanup_flyway'

      It "runs flyway migrate"
        invoke_flyway() {
          db.migrate --tool flyway --url "jdbc:h2:mem:test" 2>/dev/null || return 1
          grep -q "flyway migrate" "$MOCK_LOG"
        }
        When call invoke_flyway
        The status should be success
      End

      It "passes url to flyway"
        invoke_flyway_url() {
          db.migrate --tool flyway --url "jdbc:h2:mem:test" 2>/dev/null || return 1
          grep -q "\-url=" "$MOCK_LOG"
        }
        When call invoke_flyway_url
        The status should be success
      End

      It "uses dry-run mode"
        When call db.migrate --tool flyway --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "with mock liquibase"
      setup_liquibase() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_liquibase.log"
        mock.create_logging "liquibase" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_liquibase() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_liquibase'
      After 'cleanup_liquibase'

      It "runs liquibase update"
        invoke_liquibase() {
          db.migrate --tool liquibase --url "jdbc:h2:mem:test" 2>/dev/null || return 1
          grep -q "liquibase update" "$MOCK_LOG"
        }
        When call invoke_liquibase
        The status should be success
      End

      It "uses dry-run mode"
        When call db.migrate --tool liquibase --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "with mock alembic"
      setup_alembic() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_alembic.log"
        mock.create_logging "alembic" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_alembic() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_alembic'
      After 'cleanup_alembic'

      It "runs alembic upgrade head"
        invoke_alembic() {
          db.migrate --tool alembic 2>/dev/null || return 1
          grep -q "alembic upgrade head" "$MOCK_LOG"
        }
        When call invoke_alembic
        The status should be success
      End

      It "uses dry-run mode"
        When call db.migrate --tool alembic --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "custom tool"
      It "returns 2 when no command specified"
        When call db.migrate --tool custom
        The status should equal 2
        The stderr should include "custom migration command is required"
      End

      It "uses dry-run mode with custom"
        When call db.migrate --tool custom --command "echo migrate" --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "runs custom command"
        invoke_custom() {
          local tmpfile
          tmpfile="$(mktemp)"
          db.migrate --tool custom --command "printf done > $tmpfile" 2>/dev/null || return 1
          local result
          result="$(cat "$tmpfile")"
          rm -f "$tmpfile"
          [[ "$result" == "done" ]]
        }
        When call invoke_custom
        The status should be success
      End
    End

    Describe "with mock alembic + url"
      setup_alembic_url() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_alembic.log"
        mock.create_logging "alembic" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_alembic_url() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_alembic_url'
      After 'cleanup_alembic_url'

      It "passes url via SQLALCHEMY_DATABASE_URI"
        invoke_alembic_url() {
          db.migrate --tool alembic --url "sqlite:///test.db" 2>/dev/null || return 1
          grep -q "alembic upgrade head" "$MOCK_LOG"
        }
        When call invoke_alembic_url
        The status should be success
      End
    End

    Describe "flyway without url"
      setup_flyway_nourl() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_flyway.log"
        mock.create_logging "flyway" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_flyway_nourl() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_flyway_nourl'
      After 'cleanup_flyway_nourl'

      It "runs flyway migrate without url"
        invoke_flyway_nourl() {
          db.migrate --tool flyway 2>/dev/null || return 1
          grep -q "flyway migrate" "$MOCK_LOG" && ! grep -q "\-url=" "$MOCK_LOG"
        }
        When call invoke_flyway_nourl
        The status should be success
      End

      It "logs success message"
        When call db.migrate --tool flyway
        The status should be success
        The stderr should include "flyway migrations completed"
      End
    End

    Describe "liquibase without url"
      setup_liquibase_nourl() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_liquibase.log"
        mock.create_logging "liquibase" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_liquibase_nourl() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_liquibase_nourl'
      After 'cleanup_liquibase_nourl'

      It "logs success message"
        When call db.migrate --tool liquibase
        The status should be success
        The stderr should include "liquibase migrations completed"
      End
    End

    Describe "alembic without url"
      setup_alembic_nourl() {
        mock.setup
        mock.create_exit "alembic" 0
        mock.activate
      }
      cleanup_alembic_nourl() {
        mock.cleanup
      }
      Before 'setup_alembic_nourl'
      After 'cleanup_alembic_nourl'

      It "logs success message"
        When call db.migrate --tool alembic
        The status should be success
        The stderr should include "alembic migrations completed"
      End
    End

    Describe "custom run (non-dry-run)"
      It "logs success on custom run"
        When call db.migrate --tool custom --command "true"
        The status should be success
        The stderr should include "custom migration completed"
      End
    End
  End

  Describe "db.status"
    It "returns 2 when no tool specified"
      When call db.status --url "jdbc:h2:mem:test"
      The status should equal 2
      The stderr should include "migration tool is required"
    End

    It "returns 2 for unknown option"
      When call db.status --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 for unsupported tool"
      When call db.status --tool unsupported
      The status should equal 2
      The stderr should include "unsupported migration tool"
    End

    Describe "with mock flyway"
      setup_flyway_status() {
        mock.setup
        mock.create_exit "flyway" 0
        mock.activate
      }
      cleanup_flyway_status() {
        mock.cleanup
      }
      Before 'setup_flyway_status'
      After 'cleanup_flyway_status'

      It "runs flyway info"
        When call db.status --tool flyway
        The status should be success
        The stderr should include "checking migration status"
      End

      It "passes url to flyway info"
        When call db.status --tool flyway --url "jdbc:h2:mem:test"
        The status should be success
        The stderr should include "checking migration status"
      End
    End

    Describe "with mock liquibase"
      setup_liquibase_status() {
        mock.setup
        mock.create_exit "liquibase" 0
        mock.activate
      }
      cleanup_liquibase_status() {
        mock.cleanup
      }
      Before 'setup_liquibase_status'
      After 'cleanup_liquibase_status'

      It "runs liquibase status"
        When call db.status --tool liquibase
        The status should be success
        The stderr should include "checking migration status"
      End
    End

    Describe "with mock alembic"
      setup_alembic_status() {
        mock.setup
        mock.create_exit "alembic" 0
        mock.activate
      }
      cleanup_alembic_status() {
        mock.cleanup
      }
      Before 'setup_alembic_status'
      After 'cleanup_alembic_status'

      It "runs alembic current"
        When call db.status --tool alembic
        The status should be success
        The stderr should include "checking migration status"
      End
    End
  End
End
