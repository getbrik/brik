Describe "shared-libs/jenkins brikPipeline.groovy - artifact layout"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikPipeline.groovy"

  It "junit testResults pattern points at brik-artifacts/test/"
    When call grep -F "junit testResults: 'brik-artifacts/test/junit.xml,brik-artifacts/test/junit/**/*.xml'" "$GROOVY"
    The status should be success
    The output should be present
  End

  It "no longer ships an intermediate coverage/reports archiveArtifacts block"
    When call grep -F "'coverage/**,reports/**'" "$GROOVY"
    The status should not equal 0
  End

  It "still archives brik-artifacts in the final block"
    When call grep -F "archiveArtifacts artifacts: 'brik-artifacts/**/*'" "$GROOVY"
    The status should be success
    The output should be present
  End
End
