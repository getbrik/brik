Describe "stages.package"
  Include "$BRIK_HOME/runtime/bash/lib/runtime/stage.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/package.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_VERSION="1.0.0"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE"
    unset BRIK_PACKAGE_DOCKER_IMAGE BRIK_VERSION 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.package >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "sets BRIK_PACKAGE_STATUS to skipped when no docker image configured"
    run_package_skip() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
      stages.package "$ctx" >/dev/null 2>&1
      grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
    }
    When call run_package_skip
    The output should equal "skipped"
  End

  Describe "with docker config"
    setup_docker() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: registry.example.com/myapp
    dockerfile: Dockerfile.prod
    context: .
    build_args: NODE_ENV=production
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_docker'

    It "returns 0 when build.docker.run succeeds"
      run_package_success() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
      }
      When call run_package_success
      The status should be success
    End

    It "sets BRIK_PACKAGE_STATUS to success"
      run_package_ctx() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_package_ctx
      The output should equal "success"
    End

    It "sets BRIK_PACKAGE_STATUS to failed when build fails"
      run_package_fail() {
        brik.use() { :; }
        build.docker.run() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1 || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_package_fail
      The output should equal "failed"
    End

    It "passes docker arguments to build.docker.run"
      run_package_args() {
        brik.use() { :; }
        build.docker.run() { printf '%s ' "$@"; printf '\n'; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_package_args
      The output should include "--file Dockerfile.prod"
      The output should include "--tag registry.example.com/myapp:1.0.0"
      The output should include "--build-arg NODE_ENV=production"
    End

    It "logs docker image name"
      run_package_log() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx"
      }
      When call run_package_log
      The error should include "building image: registry.example.com/myapp:1.0.0"
    End
  End

  Describe "with docker publish config"
    setup_publish_docker() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: registry.example.com/myapp
publish:
  docker:
    image: registry.example.com/myapp
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_docker'

    It "publishes docker image after build"
      run_publish_docker() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLED=""
        publish.run() { PUBLISH_CALLED="$*"; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLED"
      }
      When call run_publish_docker
      The output should include "--target docker"
    End

    It "sets failed when docker publish fails"
      run_publish_docker_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_docker_fail
      The output should equal "failed"
    End
  End

  Describe "with npm publish config"
    setup_publish_npm() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: registry.example.com/myapp
publish:
  npm:
    token_var: NPM_TOKEN
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_npm'

    It "publishes npm package after build"
      run_publish_npm() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_npm
      The output should include "--target npm"
    End

    It "sets failed when npm publish fails"
      run_publish_npm_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() {
          case "$*" in
            *docker*) return 0 ;;
            *npm*) return 1 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_npm_fail
      The output should equal "failed"
    End
  End

  Describe "with maven publish config"
    setup_publish_maven() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: java
package:
  docker:
    image: registry.example.com/myapp
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: MAVEN_USER
    password_var: MAVEN_PASSWORD
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_maven'

    It "publishes maven artifact after build"
      run_publish_maven() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_maven
      The output should include "--target maven"
    End

    It "sets failed when maven publish fails"
      run_publish_maven_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() {
          case "$*" in
            *docker*) return 0 ;;
            *maven*) return 1 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_maven_fail
      The output should equal "failed"
    End
  End

  Describe "with pypi publish config"
    setup_publish_pypi() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: python
package:
  docker:
    image: registry.example.com/myapp
publish:
  pypi:
    token_var: PYPI_TOKEN
    repository: https://nexus.example.com/repository/pypi-hosted/
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_pypi'

    It "publishes pypi package after build"
      run_publish_pypi() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_pypi
      The output should include "--target pypi"
    End

    It "sets failed when pypi publish fails"
      run_publish_pypi_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() {
          case "$*" in
            *docker*) return 0 ;;
            *pypi*) return 1 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_pypi_fail
      The output should equal "failed"
    End
  End

  Describe "with cargo publish config"
    setup_publish_cargo() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: rust
package:
  docker:
    image: registry.example.com/myapp
publish:
  cargo:
    token_var: CARGO_TOKEN
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_cargo'

    It "publishes cargo crate after build"
      run_publish_cargo() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_cargo
      The output should include "--target cargo"
    End

    It "sets failed when cargo publish fails"
      run_publish_cargo_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() {
          case "$*" in
            *docker*) return 0 ;;
            *cargo*) return 1 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_cargo_fail
      The output should equal "failed"
    End
  End

  Describe "with nuget publish config"
    setup_publish_nuget() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: dotnet
package:
  docker:
    image: registry.example.com/myapp
publish:
  nuget:
    api_key_var: NUGET_API_KEY
    source: https://nexus.example.com/repository/nuget-hosted/
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_nuget'

    It "publishes nuget package after build"
      run_publish_nuget() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_nuget
      The output should include "--target nuget"
    End

    It "sets failed when nuget publish fails"
      run_publish_nuget_fail() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        publish.run() {
          case "$*" in
            *docker*) return 0 ;;
            *nuget*) return 1 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        grep "^BRIK_PACKAGE_STATUS=" "$ctx" | cut -d= -f2
      }
      When call run_publish_nuget_fail
      The output should equal "failed"
    End
  End

  Describe "with multiple publish targets"
    setup_publish_multi() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: registry.example.com/myapp
publish:
  docker:
    image: registry.example.com/myapp
  npm:
    token_var: NPM_TOKEN
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_multi'

    It "publishes both docker and npm"
      run_publish_multi() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() { PUBLISH_CALLS="${PUBLISH_CALLS}$* "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_multi
      The output should include "--target docker"
      The output should include "--target npm"
    End

    It "stops on first publish failure (fail-fast)"
      run_publish_failfast() {
        brik.use() { :; }
        build.docker.run() { return 0; }
        local PUBLISH_CALLS=""
        publish.run() {
          PUBLISH_CALLS="${PUBLISH_CALLS}$* "
          case "$*" in
            *docker*) return 1 ;;
            *) return 0 ;;
          esac
        }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_failfast
      The output should include "--target docker"
      The output should not include "--target npm"
    End
  End
End
