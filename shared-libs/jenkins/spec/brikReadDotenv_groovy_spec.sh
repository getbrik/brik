#shellcheck shell=bash
# Contract for shared-libs/jenkins/vars/brikReadDotenv.groovy.
#
# brikReadDotenv parses a KEY=VALUE dotenv (init's .brik-logs/pipeline.env)
# into a Groovy Map consumed by brikPipeline / brikDriver to resolve runner
# images.

Describe "shared-libs/jenkins/vars/brikReadDotenv.groovy"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikReadDotenv.groovy"

  It "file exists"
    When run test -f "$GROOVY"
    The status should be success
  End

  It "splits on the first equals only"
    When run grep -qF "split('=', 2)" "$GROOVY"
    The status should be success
  End

  # A class that fails to resolve in init emits KEY='' (two literal quote
  # chars). Without unwrapping, that reads back as the truthy string "''"
  # and downstream docker.image("''") aborts. The parser strips one layer
  # of surrounding quotes so the value becomes the intended empty string.
  It "strips a single layer of surrounding quotes from the value"
    When run grep -qF "value.substring(1, value.length() - 1)" "$GROOVY"
    The status should be success
  End
End
