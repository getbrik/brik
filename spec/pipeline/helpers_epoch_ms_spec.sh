Describe "_helpers.epoch_ms"
  Include "$BRIK_PIPELINE_LIB/stage.sh"

  # _helpers.epoch_ms returns the current Unix time in milliseconds as a
  # 13-digit integer. It must use a sub-second clock source (EPOCHREALTIME
  # under bash 5+) so callers can compute non-multiple-of-1000 durations.

  Describe "shape"
    It "outputs a 13-digit integer (millisecond Unix time)"
      When call _helpers.epoch_ms
      The output should match pattern '[1-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
      The status should be success
    End
  End

  Describe "monotonicity"
    It "never decreases between consecutive calls"
      check_monotonic() {
        local a b
        a="$(_helpers.epoch_ms)"
        b="$(_helpers.epoch_ms)"
        [[ "$b" -ge "$a" ]]
      }
      When call check_monotonic
      The status should be success
    End
  End

  Describe "sub-second resolution"
    # Second-precision implementations would yield duration deltas in
    # {0, 1000, 2000, ...}. With ms precision, the delta exposes a
    # non-multiple-of-1000 component. Asserting `delta > 0 AND delta % 1000 != 0`
    # captures the design requirement without imposing a wall-clock upper
    # bound that could flake on slow CI.
    It "advances by sub-second amounts across a sleep"
      measure_sleep() {
        local s e d
        s="$(_helpers.epoch_ms)"
        sleep 0.4
        e="$(_helpers.epoch_ms)"
        d=$(( e - s ))
        [[ $d -gt 0 && $((d % 1000)) -ne 0 ]]
      }
      When call measure_sleep
      The status should be success
    End

    It "produces values not always aligned to second boundaries"
      # Out of several quick calls, at least one must NOT be divisible by
      # 1000. Second-precision implementations always return N*1000.
      not_all_aligned() {
        local i v
        for i in 1 2 3 4 5 6 7 8 9 10; do
          v="$(_helpers.epoch_ms)"
          [[ $((v % 1000)) -ne 0 ]] && return 0
          sleep 0.05
        done
        return 1
      }
      When call not_all_aligned
      The status should be success
    End
  End
End
