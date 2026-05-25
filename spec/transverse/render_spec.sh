Describe "render.sh (transverse rendering primitives)"
  Include "$BRIK_TRANSVERSE_LIB/render.sh"

  Describe "render.repeat"
    It "repeats an ASCII character N times"
      When call render.repeat "-" 5
      The output should equal "-----"
      The status should be success
    End

    It "repeats a multi-byte UTF-8 char (box-drawing) safely"
      When call render.repeat "─" 4
      The output should equal "────"
    End

    It "emits nothing when N is 0"
      When call render.repeat "x" 0
      The output should equal ""
    End
  End

  Describe "render.section"
    It "prints the title prefixed by a box-drawing horizontal marker"
      When call render.section "Stages"
      The output should equal "─ Stages"
    End
  End

  Describe "render.kv"
    It "prints '  key  value' with default 2-space indent and 2-space separator"
      # key "context" (7) -> padded to 9 -> value follows directly
      When call render.kv "context" "snapshot"
      The output should equal "  context  snapshot"
    End

    It "pads the key column to --key-width when it fits the minimum 2-space gap"
      # key "context" (7) + 2 = 9; --key-width 12 wins -> 5 trailing pad spaces
      When call render.kv "context" "snapshot" --key-width 12
      The output should equal "  context     snapshot"
    End

    It "honors a longer key when --key-width is shorter (still enforces 2-space gap)"
      # key "fingerprint" (11) + 2 = 13; --key-width 4 ignored
      When call render.kv "fingerprint" "abc" --key-width 4
      The output should equal "  fingerprint  abc"
    End

    It "respects --indent"
      When call render.kv "k" "v" --indent 0
      The output should equal "k  v"
    End

    It "omits the trailing newline with --no-newline"
      newline_test() { render.kv "a" "b" --no-newline; printf 'X'; }
      When call newline_test
      The output should equal "  a  bX"
    End

    It "pads to --width on the right"
      # "  k  v" = 6 chars; --width 12 -> 6 trailing spaces
      When call render.kv "k" "v" --width 12
      The output should equal "  k  v      "
    End

    It "truncates content longer than --width"
      # content "  key  very-long-value-here" truncated to 10 chars
      When call render.kv "key" "very-long-value-here" --width 10
      The output should equal "  key  ver"
    End

    It "produces the banner-style fixed-width line (key-width + width + no-newline)"
      # key "runner" (6) + 2 = 8; content "  runner  img:tag" = 17 chars
      # --width 30 -> 13 trailing spaces, no newline
      runner_line() { render.kv "runner" "img:tag" --key-width 6 --width 30 --no-newline; }
      When call runner_line
      The output should equal "  runner  img:tag             "
    End
  End

  Describe "render.center"
    It "returns text unchanged when --width is shorter than text"
      When call render.center "hello" --width 3
      The output should equal "hello"
    End

    It "pads symmetrically when slack is even"
      When call render.center "abc" --width 9
      The output should equal "   abc   "
    End

    It "pads with the extra char on the right when slack is odd"
      When call render.center "abc" --width 8
      The output should equal "  abc   "
    End

    It "omits trailing newline with --no-newline"
      cn() { render.center "x" --width 5 --no-newline; printf '|'; }
      When call cn
      The output should equal "  x  |"
    End

    It "defaults to no padding when --width is omitted"
      When call render.center "hi"
      The output should equal "hi"
    End
  End

  Describe "render.blank"
    It "prints N spaces followed by a newline"
      blank_test() { render.blank 5; }
      When call blank_test
      The line 1 of output should equal "     "
      The lines of output should equal 1
    End

    It "prints a bare newline when N is omitted"
      blank_zero() { render.blank | wc -c | tr -d ' '; }
      When call blank_zero
      The output should equal "1"
    End

    It "prints a bare newline when N is 0"
      blank_zero_n() { render.blank 0 | wc -c | tr -d ' '; }
      When call blank_zero_n
      The output should equal "1"
    End
  End

  Describe "render.box"
    It "wraps a single line with top/bottom rules and side borders"
      single_line_box() { printf 'hello\n' | render.box; }
      When call single_line_box
      The line 1 of output should equal "┌─────┐"
      The line 2 of output should equal "│hello│"
      The line 3 of output should equal "└─────┘"
    End

    It "auto-detects inner width from the first line"
      multi_box() {
        { printf 'abcdef\n'; printf 'xy\n'; } | render.box
      }
      When call multi_box
      The line 1 of output should equal "┌──────┐"
      The line 2 of output should equal "│abcdef│"
      The line 3 of output should equal "│xy    │"
      The line 4 of output should equal "└──────┘"
    End

    It "honors --inner-width and pads shorter lines"
      forced_box() { printf 'ab\n' | render.box --inner-width 6; }
      When call forced_box
      The line 1 of output should equal "┌──────┐"
      The line 2 of output should equal "│ab    │"
      The line 3 of output should equal "└──────┘"
    End

    It "truncates lines longer than --inner-width"
      trunc_box() { printf 'abcdef\n' | render.box --inner-width 3; }
      When call trunc_box
      The line 2 of output should equal "│abc│"
    End

    It "composes with render.center, render.blank, render.kv"
      compose_box() {
        {
          render.center "TITLE" --width 20
          render.blank 20
          render.kv "k" "v" --key-width 3 --width 20
        } | render.box --inner-width 20
      }
      When call compose_box
      # "  k  v" (6 chars: 2 indent + key "k" padded to 3 + value)
      # padded to 20 -> 14 trailing spaces
      The line 1 of output should equal "┌────────────────────┐"
      The line 2 of output should equal "│       TITLE        │"
      The line 3 of output should equal "│                    │"
      The line 4 of output should equal "│  k  v              │"
      The line 5 of output should equal "└────────────────────┘"
    End

    It "emits nothing on empty input"
      empty_box() { printf '' | render.box; }
      When call empty_box
      The output should equal ""
    End
  End

  Describe "render.color_enabled"
    It "returns true when BRIK_RENDER_FORCE_COLOR=1 (wins over everything)"
      force_color() {
        BRIK_RENDER_FORCE_COLOR=1 BRIK_RENDER_NO_COLOR=1 NO_COLOR=1 \
            GITLAB_CI=true JENKINS_URL=foo render.color_enabled
      }
      When call force_color
      The status should be success
    End

    It "returns false when BRIK_RENDER_NO_COLOR=1 (and no FORCE)"
      no_color_brik() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 GITLAB_CI=true JENKINS_URL=foo render.color_enabled
      }
      When call no_color_brik
      The status should be failure
    End

    It "returns false when NO_COLOR is set (and no FORCE)"
      no_color_std() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR
        NO_COLOR=1 GITLAB_CI=true render.color_enabled
      }
      When call no_color_std
      The status should be failure
    End

    It "returns true under GitLab CI without TTY"
      gitlab_no_tty() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR NO_COLOR JENKINS_URL
        GITLAB_CI=true render.color_enabled 1 < /dev/null
      }
      When call gitlab_no_tty
      The status should be success
    End

    It "returns true under Jenkins without TTY"
      jenkins_no_tty() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR NO_COLOR GITLAB_CI
        JENKINS_URL="http://j" render.color_enabled 1 < /dev/null
      }
      When call jenkins_no_tty
      The status should be success
    End

    It "returns false in plain non-TTY shell with no CI markers"
      plain_no_tty() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR NO_COLOR \
              GITLAB_CI JENKINS_URL
        render.color_enabled 1 < /dev/null
      }
      When call plain_no_tty
      The status should be failure
    End

    It "returns false when TERM=dumb outside CI (no CI marker, no TTY)"
      term_dumb_plain() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR \
              GITLAB_CI JENKINS_URL NO_COLOR
        TERM=dumb render.color_enabled 1 < /dev/null
      }
      When call term_dumb_plain
      The status should be failure
    End

    It "honors GITLAB_CI over TERM=dumb (CI runner images set TERM=dumb)"
      term_dumb_in_gitlab() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR NO_COLOR
        TERM=dumb GITLAB_CI=true render.color_enabled 1 < /dev/null
      }
      When call term_dumb_in_gitlab
      The status should be success
    End

    It "honors JENKINS_URL over TERM=dumb (CI runner images set TERM=dumb)"
      term_dumb_in_jenkins() {
        unset BRIK_RENDER_FORCE_COLOR BRIK_RENDER_NO_COLOR NO_COLOR GITLAB_CI
        TERM=dumb JENKINS_URL=http://jenkins.example render.color_enabled 1 < /dev/null
      }
      When call term_dumb_in_jenkins
      The status should be success
    End

    It "FORCE_COLOR still wins over TERM=dumb"
      term_dumb_forced() {
        TERM=dumb BRIK_RENDER_FORCE_COLOR=1 render.color_enabled
      }
      When call term_dumb_forced
      The status should be success
    End
  End

  Describe "render.color"
    It "emits the green ANSI escape when FORCE_COLOR=1"
      green_force() { BRIK_RENDER_FORCE_COLOR=1 render.color green; }
      When call green_force
      The output should equal "$(printf '\033[32m')"
    End

    It "emits the reset ANSI escape when FORCE_COLOR=1"
      reset_force() { BRIK_RENDER_FORCE_COLOR=1 render.color reset; }
      When call reset_force
      The output should equal "$(printf '\033[0m')"
    End

    It "returns nothing when NO_COLOR=1"
      nothing_no_color() {
        unset BRIK_RENDER_FORCE_COLOR
        NO_COLOR=1 render.color green; printf '|'
      }
      When call nothing_no_color
      The output should equal "|"
    End

    It "returns nothing when BRIK_RENDER_NO_COLOR=1"
      nothing_brik_no_color() {
        unset BRIK_RENDER_FORCE_COLOR NO_COLOR
        BRIK_RENDER_NO_COLOR=1 render.color green; printf '|'
      }
      When call nothing_brik_no_color
      The output should equal "|"
    End

    It "returns non-zero for an unknown color name"
      unknown_color() { BRIK_RENDER_FORCE_COLOR=1 render.color "fuchsia42"; }
      When call unknown_color
      The status should be failure
    End

    It "supports all named colors"
      all_colors() {
        BRIK_RENDER_FORCE_COLOR=1
        for c in reset bold dim red green yellow blue magenta cyan white; do
          render.color "$c" >/dev/null || { echo "FAIL $c"; return 1; }
        done
        echo OK
      }
      When call all_colors
      The output should equal "OK"
    End
  End

  Describe "render.icon"
    It "emits a check mark for success"
      When call render.icon success
      The output should equal "✅"
    End

    It "emits a cross mark for error"
      When call render.icon error
      The output should equal "❌"
    End

    It "emits a warning sign for warn"
      When call render.icon warn
      The output should equal "⚠️"
    End

    It "emits a skip arrow for skipped"
      When call render.icon skipped
      The output should equal "⏭️"
    End

    It "emits an info glyph for info"
      When call render.icon info
      The output should equal "ℹ️"
    End

    It "emits a magnifier for debug"
      When call render.icon debug
      The output should equal "🔍"
    End

    It "accepts ok as alias for success"
      When call render.icon ok
      The output should equal "✅"
    End

    It "accepts fail as alias for error"
      When call render.icon fail
      The output should equal "❌"
    End

    It "returns non-zero for unknown levels"
      When call render.icon banana
      The status should be failure
    End

    It "does not emit a trailing newline"
      no_nl() { render.icon success; printf '|'; }
      When call no_nl
      The output should equal "✅|"
    End
  End

  Describe "render.status"
    It "emits [OK] for success without text (no color env)"
      ok_no_color() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status success
      }
      When call ok_no_color
      The output should equal "[OK]"
    End

    It "emits [OK] success when text is given"
      ok_text() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status success "passed"
      }
      When call ok_text
      The output should equal "[OK] passed"
    End

    It "wraps the OK label in green when colors are on"
      ok_green() { BRIK_RENDER_FORCE_COLOR=1 render.status success; }
      When call ok_green
      The output should equal "[$(printf '\033[32m')OK$(printf '\033[0m')]"
    End

    It "emits [WARN] for warning"
      warn_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status warning
      }
      When call warn_label
      The output should equal "[WARN]"
    End

    It "emits [ERROR] for error"
      err_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status error
      }
      When call err_label
      The output should equal "[ERROR]"
    End

    It "emits [SKIP] for skipped"
      skip_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status skipped
      }
      When call skip_label
      The output should equal "[SKIP]"
    End

    It "emits [INFO] for info"
      info_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status info
      }
      When call info_label
      The output should equal "[INFO]"
    End

    It "uses the level itself when not in the known set"
      custom_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status "PENDING"
      }
      When call custom_label
      The output should equal "[PENDING]"
    End

    It "accepts 'warn' as alias for 'warning'"
      warn_alias() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status warn
      }
      When call warn_alias
      The output should equal "[WARN]"
    End

    It "accepts 'skip' as alias for 'skipped'"
      skip_alias() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status skip
      }
      When call skip_alias
      The output should equal "[SKIP]"
    End

    It "emits [DEBUG] for debug (dim)"
      debug_label() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status debug
      }
      When call debug_label
      The output should equal "[DEBUG]"
    End

    It "wraps the DEBUG label in dim when colors are on"
      debug_dim() { BRIK_RENDER_FORCE_COLOR=1 render.status debug; }
      When call debug_dim
      The output should equal "[$(printf '\033[2m')DEBUG$(printf '\033[0m')]"
    End

    It "does not emit a trailing newline"
      no_newline() {
        unset BRIK_RENDER_FORCE_COLOR
        BRIK_RENDER_NO_COLOR=1 render.status success; printf 'X'
      }
      When call no_newline
      The output should equal "[OK]X"
    End
  End

  Describe "render.table"
    It "writes nothing when stdin is empty"
      When call render.table
      The status should be success
      The stdout should equal ""
      The stderr should equal ""
    End

    It "renders a header-only table with top and bottom rules"
      Data
        #|name|age
      End
      When call render.table --delim "|"
      The stdout should include "┌"
      The stdout should include "┐"
      The stdout should include "└"
      The stdout should include "┘"
      The stdout should include "│ name │ age │"
    End

    It "renders header, mid rule, and body rows"
      Data
        #|name|age
        #|alice|30
        #|bob|7
      End
      When call render.table --delim "|"
      The stdout should include "├"
      The stdout should include "┼"
      The stdout should include "┤"
      The stdout should include "│ alice │ 30  │"
      The stdout should include "│ bob   │ 7   │"
    End

    It "auto-sizes columns to the widest cell"
      Data
        #|stage|status
        #|init|ok
        #|container-scan|success
      End
      When call render.table --delim "|"
      The stdout should include "│ stage          │ status  │"
      The stdout should include "│ init           │ ok      │"
      The stdout should include "│ container-scan │ success │"
    End

    It "writes to stdout, not stderr"
      Data
        #|a|b
        #|1|2
      End
      When call render.table --delim "|"
      The stderr should equal ""
      The stdout should be present
    End

    It "skips blank lines from input"
      Data
        #|name|age
        #|
        #|alice|30
        #|
      End
      When call render.table --delim "|"
      The stdout should include "│ alice │ 30  │"
    End

    It "preserves multibyte glyphs in cells"
      Data
        #|stage|status
        #|sast|✓ success
      End
      When call render.table --delim "|"
      The stdout should include "│ sast  │ ✓ success │"
    End

    It "defaults to TAB delimiter"
      Data
        #|name	age
        #|alice	30
      End
      When call render.table
      The stdout should include "│ alice │ 30  │"
    End
  End
End
