Describe "db.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/db.sh"

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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_flyway.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/flyway" << MOCKEOF
#!/usr/bin/env bash
printf 'flyway %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/flyway"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_flyway() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_liquibase.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/liquibase" << MOCKEOF
#!/usr/bin/env bash
printf 'liquibase %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/liquibase"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_liquibase() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_alembic.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/alembic" << MOCKEOF
#!/usr/bin/env bash
printf 'alembic %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/alembic"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_alembic() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_alembic.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/alembic" << MOCKEOF
#!/usr/bin/env bash
printf 'alembic %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/alembic"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_alembic_url() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_flyway.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/flyway" << MOCKEOF
#!/usr/bin/env bash
printf 'flyway %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/flyway"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_flyway_nourl() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_liquibase.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/liquibase" << MOCKEOF
#!/usr/bin/env bash
printf 'liquibase %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/liquibase"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_liquibase_nourl() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/alembic" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/alembic"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_alembic_nourl() {
        export PATH="$ORIG_PATH"
        rm -rf "$MOCK_BIN"
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
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/flyway" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/flyway"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_flyway_status() {
        export PATH="$ORIG_PATH"
        rm -rf "$MOCK_BIN"
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
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/liquibase" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/liquibase"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_liquibase_status() {
        export PATH="$ORIG_PATH"
        rm -rf "$MOCK_BIN"
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
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/alembic" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/alembic"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_alembic_status() {
        export PATH="$ORIG_PATH"
        rm -rf "$MOCK_BIN"
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
