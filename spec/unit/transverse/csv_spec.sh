Describe "csv.sh (transverse CSV iteration helper)"
  Include "$BRIK_HOME/lib/transverse/csv.sh"

  # Fixtures: helper function whose name is passed to foreach.
  # Collects calls into a global array for assertions.
  setup_collector() {
    _CSV_CALLS=()
  }
  _csv_spec_collect() {
    _CSV_CALLS+=("$*")
  }

  Describe "transverse.csv.foreach"
    Before 'setup_collector'

    It "calls fn once per non-empty item"
      When call transverse.csv.foreach "a,b,c" _csv_spec_collect
      The status should be success
      The variable _CSV_CALLS[0] should equal "a"
      The variable _CSV_CALLS[1] should equal "b"
      The variable _CSV_CALLS[2] should equal "c"
    End

    It "strips whitespace around items"
      When call transverse.csv.foreach "  a ,  b  , c  " _csv_spec_collect
      The status should be success
      The variable _CSV_CALLS[0] should equal "a"
      The variable _CSV_CALLS[1] should equal "b"
      The variable _CSV_CALLS[2] should equal "c"
    End

    It "passes extra args to fn after the item"
      When call transverse.csv.foreach "x,y" _csv_spec_collect arg1 arg2
      The status should be success
      The variable _CSV_CALLS[0] should equal "x arg1 arg2"
      The variable _CSV_CALLS[1] should equal "y arg1 arg2"
    End

    It "is a no-op on empty CSV string"
      csv_size_check() {
        transverse.csv.foreach "" _csv_spec_collect
        printf '%s' "${#_CSV_CALLS[@]}"
      }
      When call csv_size_check
      The status should be success
      The output should equal "0"
    End

    It "skips empty items between commas"
      csv_size_check() {
        transverse.csv.foreach "a,,b,,," _csv_spec_collect
        printf '%s\n%s\n%s' "${#_CSV_CALLS[@]}" "${_CSV_CALLS[0]}" "${_CSV_CALLS[1]}"
      }
      When call csv_size_check
      The status should be success
      The line 1 of output should equal "2"
      The line 2 of output should equal "a"
      The line 3 of output should equal "b"
    End

    It "handles trailing and leading commas"
      csv_size_check() {
        transverse.csv.foreach ",a,b," _csv_spec_collect
        printf '%s\n%s\n%s' "${#_CSV_CALLS[@]}" "${_CSV_CALLS[0]}" "${_CSV_CALLS[1]}"
      }
      When call csv_size_check
      The status should be success
      The line 1 of output should equal "2"
      The line 2 of output should equal "a"
      The line 3 of output should equal "b"
    End

    It "handles single item without commas"
      csv_size_check() {
        transverse.csv.foreach "solo" _csv_spec_collect
        printf '%s\n%s' "${#_CSV_CALLS[@]}" "${_CSV_CALLS[0]}"
      }
      When call csv_size_check
      The status should be success
      The line 1 of output should equal "1"
      The line 2 of output should equal "solo"
    End

    It "restores IFS after iteration"
      local _before_ifs="${IFS}"
      When call transverse.csv.foreach "a,b" _csv_spec_collect
      The status should be success
      The variable IFS should equal "${_before_ifs}"
    End

    It "propagates failure from fn but continues iteration"
      _csv_spec_fail_on_b() {
        _CSV_CALLS+=("$1")
        [[ "$1" == "b" ]] && return 42
        return 0
      }
      csv_size_check() {
        transverse.csv.foreach "a,b,c" _csv_spec_fail_on_b
        local rc=$?
        printf '%s\n%s\n%s\n%s' "$rc" "${_CSV_CALLS[0]}" "${_CSV_CALLS[1]}" "${_CSV_CALLS[2]}"
      }
      When call csv_size_check
      The line 1 of output should equal "42"
      The line 2 of output should equal "a"
      The line 3 of output should equal "b"
      The line 4 of output should equal "c"
    End

    It "returns last non-zero code when multiple callbacks fail"
      _csv_spec_fail_differently() {
        _CSV_CALLS+=("$1")
        case "$1" in
          a) return 10 ;;
          b) return 20 ;;
          c) return 30 ;;
        esac
      }
      csv_size_check() {
        transverse.csv.foreach "a,b,c" _csv_spec_fail_differently
        local rc=$?
        printf '%s\n%s' "$rc" "${#_CSV_CALLS[@]}"
      }
      When call csv_size_check
      The line 1 of output should equal "30"
      The line 2 of output should equal "3"
    End

    It "preserves internal whitespace inside items"
      csv_size_check() {
        transverse.csv.foreach "hello world, foo bar " _csv_spec_collect
        printf '%s\n%s\n%s' "${#_CSV_CALLS[@]}" "${_CSV_CALLS[0]}" "${_CSV_CALLS[1]}"
      }
      When call csv_size_check
      The line 1 of output should equal "2"
      The line 2 of output should equal "hello world"
      The line 3 of output should equal "foo bar"
    End
  End
End
