Describe "logging.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"

  Describe "log.info"
    It "emits a formatted line to stderr"
      When call log.info "hello world"
      The status should be success
      The stderr should include "[INFO]"
      The stderr should include "hello world"
    End

    It "includes a timestamp"
      When call log.info "test"
      The stderr should match pattern "*T*:*:*[INFO]*"
    End

    It "includes the scope from BRIK_LOG_SCOPE"
      export BRIK_LOG_SCOPE="build"
      When call log.info "scoped message"
      The stderr should include "[build]"
      unset BRIK_LOG_SCOPE
    End

    It "uses 'brik' as default scope"
      unset BRIK_LOG_SCOPE
      When call log.info "default scope"
      The stderr should include "[brik]"
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
      The stderr should include "[DEBUG]"
      The stderr should include "visible"
      unset BRIK_LOG_LEVEL
    End
  End

  Describe "log.warn"
    It "emits a WARN level line"
      When call log.warn "caution"
      The stderr should include "[WARN]"
      The stderr should include "caution"
    End
  End

  Describe "log.error"
    It "emits an ERROR level line"
      When call log.error "failure"
      The stderr should include "[ERROR]"
      The stderr should include "failure"
    End

    It "is emitted even when BRIK_LOG_LEVEL=error"
      export BRIK_LOG_LEVEL="error"
      When call log.error "critical"
      The stderr should include "[ERROR]"
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
      The stderr should include "[WARN]"
      unset BRIK_LOG_LEVEL
    End
  End
End
