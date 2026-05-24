Describe "logging.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"

  Describe "log.info"
    It "emits a formatted line to stderr (no brackets, padded label)"
      When call log.info "hello world"
      The status should be success
      # New format: "<ts>  INFO   <scope>  <msg>" (label padded to 5)
      The stderr should include "  INFO   "
      The stderr should include "hello world"
    End

    It "includes a timestamp"
      When call log.info "test"
      The stderr should match pattern "*T*:*:*INFO*"
    End

    It "includes the scope from BRIK_LOG_SCOPE (no brackets)"
      export BRIK_LOG_SCOPE="build"
      When call log.info "scoped message"
      The stderr should include "  build  "
      unset BRIK_LOG_SCOPE
    End

    It "uses 'brik' as default scope"
      unset BRIK_LOG_SCOPE
      When call log.info "default scope"
      The stderr should include "  brik  "
    End
  End

  Describe "log.debug"
    It "is suppressed at default log level (info)"
      unset BRIK_LOG_LEVEL
      When call log.debug "hidden"
      The status should be success
      The stderr should equal ""
    End

    It "is emitted when BRIK_LOG_LEVEL=debug"
      export BRIK_LOG_LEVEL="debug"
      When call log.debug "visible"
      The stderr should include "DEBUG"
      The stderr should include "visible"
      unset BRIK_LOG_LEVEL
    End
  End

  Describe "log.warn"
    It "emits a WARN level line"
      When call log.warn "caution"
      The stderr should include "WARN"
      The stderr should include "caution"
    End
  End

  Describe "log.error"
    It "emits an ERROR level line"
      When call log.error "failure"
      The stderr should include "ERROR"
      The stderr should include "failure"
    End

    It "is emitted even when BRIK_LOG_LEVEL=error"
      export BRIK_LOG_LEVEL="error"
      When call log.error "critical"
      The stderr should include "ERROR"
      unset BRIK_LOG_LEVEL
    End
  End

  Describe "log.success"
    It "emits an OK level line"
      When call log.success "stage done"
      The stderr should include "  OK    "
      The stderr should include "stage done"
    End

    It "filters identically to info (suppressed at level=warn)"
      export BRIK_LOG_LEVEL="warn"
      When call log.success "suppressed"
      The stderr should equal ""
      unset BRIK_LOG_LEVEL
    End
  End

  Describe "level filtering"
    It "suppresses info when BRIK_LOG_LEVEL=warn"
      export BRIK_LOG_LEVEL="warn"
      When call log.info "suppressed"
      The stderr should equal ""
      unset BRIK_LOG_LEVEL
    End

    It "shows warn when BRIK_LOG_LEVEL=warn"
      export BRIK_LOG_LEVEL="warn"
      When call log.warn "visible"
      The stderr should include "WARN"
      unset BRIK_LOG_LEVEL
    End
  End

  Describe "color support"
    It "emits no ANSI escapes by default in non-TTY context"
      unset BRIK_LOG_FORCE_COLOR
      unset BRIK_LOG_NO_COLOR
      unset NO_COLOR GITLAB_CI JENKINS_URL
      When call log.warn "no colors here"
      The stderr should not include $'\033'"["
    End

    It "wraps the whole line in red when BRIK_LOG_FORCE_COLOR=1 (error)"
      export BRIK_LOG_FORCE_COLOR=1
      When call log.error "boom"
      # Whole-line color: prefix red escape, suffix reset escape
      The stderr should start with $'\033'"[31m"
      The stderr should include "ERROR"
      The stderr should include "boom"
      The stderr should include $'\033'"[0m"
      unset BRIK_LOG_FORCE_COLOR
    End

    It "uses green for the success line when colors are forced"
      export BRIK_LOG_FORCE_COLOR=1
      When call log.success "yay"
      The stderr should start with $'\033'"[32m"
      The stderr should include "OK"
      unset BRIK_LOG_FORCE_COLOR
    End

    It "uses yellow for the warn line when colors are forced"
      export BRIK_LOG_FORCE_COLOR=1
      When call log.warn "careful"
      The stderr should start with $'\033'"[33m"
      The stderr should include "WARN"
      unset BRIK_LOG_FORCE_COLOR
    End

    It "uses blue for the info line when colors are forced"
      export BRIK_LOG_FORCE_COLOR=1
      When call log.info "neutral"
      The stderr should start with $'\033'"[34m"
      The stderr should include "INFO"
      unset BRIK_LOG_FORCE_COLOR
    End

    It "respects NO_COLOR even when stderr would otherwise allow color"
      export NO_COLOR=1
      When call log.error "boom"
      The stderr should not include $'\033'"["
      unset NO_COLOR
    End

    It "BRIK_LOG_NO_COLOR=1 disables color even when GITLAB_CI=true"
      export BRIK_LOG_NO_COLOR=1
      export GITLAB_CI=true
      When call log.error "boom"
      The stderr should not include $'\033'"["
      unset BRIK_LOG_NO_COLOR
      unset GITLAB_CI
    End

    It "BRIK_LOG_FORCE_COLOR overrides BRIK_LOG_NO_COLOR"
      export BRIK_LOG_NO_COLOR=1
      export BRIK_LOG_FORCE_COLOR=1
      When call log.warn "test"
      The stderr should include $'\033'"[33m"
      unset BRIK_LOG_NO_COLOR
      unset BRIK_LOG_FORCE_COLOR
    End
  End
End
