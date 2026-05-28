#shellcheck shell=bash
# Contract for lib/stages/verify/_cfg.sh
#
# Project-config detection helpers shared by verify.lint and verify.format.
# Each _verify_cfg.has_* helper returns 0 when the workspace has explicitly
# opted into a tool via a recognised config file or build-file marker, and
# 1 otherwise. The verify.* dispatchers call these to skip cleanly instead
# of running a tool with default rules the project never agreed to enforce.
# All helpers are pure bash (no grep/awk) so they keep working under
# PATH-isolated test environments.

Describe "lib/stages/verify/_cfg.sh"
  Include "$BRIK_HOME/lib/stages/verify/_cfg.sh"

  setup_ws() { CFG_WS="$(mktemp -d)"; }
  cleanup_ws() { rm -rf "$CFG_WS"; }
  Before 'setup_ws'
  After 'cleanup_ws'

  Describe "_verify_cfg.has_ruff"
    It "detects a root ruff.toml"
      check() { : > "$CFG_WS/ruff.toml"; _verify_cfg.has_ruff "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a root .ruff.toml"
      check() { : > "$CFG_WS/.ruff.toml"; _verify_cfg.has_ruff "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a [tool.ruff] table in pyproject.toml"
      check() { printf '[tool.ruff]\nline-length = 100\n' > "$CFG_WS/pyproject.toml"; _verify_cfg.has_ruff "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a nested [tool.ruff.lint] table in pyproject.toml"
      check() { printf '[tool.ruff.lint]\nselect = ["E"]\n' > "$CFG_WS/pyproject.toml"; _verify_cfg.has_ruff "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure for a pyproject.toml without a ruff table"
      check() { printf '[tool.black]\n' > "$CFG_WS/pyproject.toml"; _verify_cfg.has_ruff "$CFG_WS"; }
      When call check
      The status should be failure
    End

    It "returns failure for an empty workspace"
      When call _verify_cfg.has_ruff "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_black"
    It "detects a [tool.black] table in pyproject.toml"
      check() { printf '[tool.black]\nline-length = 88\n' > "$CFG_WS/pyproject.toml"; _verify_cfg.has_black "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure for a pyproject.toml without a black table"
      check() { printf '[tool.ruff]\n' > "$CFG_WS/pyproject.toml"; _verify_cfg.has_black "$CFG_WS"; }
      When call check
      The status should be failure
    End

    It "returns failure when pyproject.toml is absent"
      When call _verify_cfg.has_black "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_checkstyle"
    It "detects a root checkstyle.xml"
      check() { : > "$CFG_WS/checkstyle.xml"; _verify_cfg.has_checkstyle "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects maven-checkstyle-plugin in pom.xml"
      check() { printf '<plugin><artifactId>maven-checkstyle-plugin</artifactId></plugin>\n' > "$CFG_WS/pom.xml"; _verify_cfg.has_checkstyle "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a checkstyle reference in build.gradle"
      check() { printf "apply plugin: 'checkstyle'\n" > "$CFG_WS/build.gradle"; _verify_cfg.has_checkstyle "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a checkstyle reference in build.gradle.kts"
      check() { printf 'checkstyle { toolVersion = "10.0" }\n' > "$CFG_WS/build.gradle.kts"; _verify_cfg.has_checkstyle "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure for a pom.xml without checkstyle"
      check() { printf '<project></project>\n' > "$CFG_WS/pom.xml"; _verify_cfg.has_checkstyle "$CFG_WS"; }
      When call check
      The status should be failure
    End

    It "returns failure for an empty workspace"
      When call _verify_cfg.has_checkstyle "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_dotnet_format"
    It "detects a root .editorconfig"
      check() { : > "$CFG_WS/.editorconfig"; _verify_cfg.has_dotnet_format "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure without an .editorconfig"
      When call _verify_cfg.has_dotnet_format "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_prettier"
    It "detects a .prettierrc file"
      check() { : > "$CFG_WS/.prettierrc"; _verify_cfg.has_prettier "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a prettier.config.js file"
      check() { : > "$CFG_WS/prettier.config.js"; _verify_cfg.has_prettier "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a prettier key in package.json"
      check() { printf '{ "prettier": { "semi": false } }\n' > "$CFG_WS/package.json"; _verify_cfg.has_prettier "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure for a package.json without a prettier key"
      check() { printf '{ "name": "demo" }\n' > "$CFG_WS/package.json"; _verify_cfg.has_prettier "$CFG_WS"; }
      When call check
      The status should be failure
    End

    It "returns failure for an empty workspace"
      When call _verify_cfg.has_prettier "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_biome"
    It "detects a biome.json"
      check() { : > "$CFG_WS/biome.json"; _verify_cfg.has_biome "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a biome.jsonc"
      check() { : > "$CFG_WS/biome.jsonc"; _verify_cfg.has_biome "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure without a biome config"
      When call _verify_cfg.has_biome "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_rustfmt"
    It "detects a rustfmt.toml"
      check() { : > "$CFG_WS/rustfmt.toml"; _verify_cfg.has_rustfmt "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a .rustfmt.toml"
      check() { : > "$CFG_WS/.rustfmt.toml"; _verify_cfg.has_rustfmt "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure without a rustfmt config"
      When call _verify_cfg.has_rustfmt "$CFG_WS"
      The status should be failure
    End
  End

  Describe "_verify_cfg.has_google_java_format"
    It "detects fmt-maven-plugin in pom.xml"
      check() { printf '<plugin><artifactId>fmt-maven-plugin</artifactId></plugin>\n' > "$CFG_WS/pom.xml"; _verify_cfg.has_google_java_format "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects spotless-maven-plugin in pom.xml"
      check() { printf '<plugin><artifactId>spotless-maven-plugin</artifactId></plugin>\n' > "$CFG_WS/pom.xml"; _verify_cfg.has_google_java_format "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a spotless reference in build.gradle"
      check() { printf "apply plugin: 'com.diffplug.spotless'\n" > "$CFG_WS/build.gradle"; _verify_cfg.has_google_java_format "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "detects a google-java-format reference in build.gradle.kts"
      check() { printf 'googleJavaFormat() // google-java-format\n' > "$CFG_WS/build.gradle.kts"; _verify_cfg.has_google_java_format "$CFG_WS"; }
      When call check
      The status should be success
    End

    It "returns failure for a pom.xml without a formatter plugin"
      check() { printf '<project></project>\n' > "$CFG_WS/pom.xml"; _verify_cfg.has_google_java_format "$CFG_WS"; }
      When call check
      The status should be failure
    End

    It "returns failure for an empty workspace"
      When call _verify_cfg.has_google_java_format "$CFG_WS"
      The status should be failure
    End
  End
End
