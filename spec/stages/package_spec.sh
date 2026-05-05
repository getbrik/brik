Describe "stages.package"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/env.sh"
  Include "$BRIK_HOME/lib/stages/package.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_APP_VERSION="1.0.0"
    export BRIK_RUN_ID="package-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_PACKAGE_DOCKER_IMAGE BRIK_APP_VERSION BRIK_RUN_ID 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  read_package_status() {
    jq -r '.stages[] | select(.name == "package") | .tech.status // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_package_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "package") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_package_business_json() {
    local key="$1"
    jq -c --arg k "$key" \
      '.stages[] | select(.name == "package") | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  It "is callable as a function"
    callable_check() { declare -f stages.package >/dev/null; }
    When call callable_check
    The status should be success
  End

  Describe "C.4 enrichment with docker image configured"
    setup_pkg_full() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: registry.example.com/myapp
    dockerfile: deploy/Dockerfile
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_pkg_full'

    It "records package.tech.packager as docker"
      run_pkg_packager() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        read_package_tech "packager"
      }
      When call run_pkg_packager
      The output should equal "docker"
    End

    It "records package.tech.dockerfile from .package.docker.dockerfile"
      run_pkg_dockerfile() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        read_package_tech "dockerfile"
      }
      When call run_pkg_dockerfile
      The output should equal "deploy/Dockerfile"
    End

    It "records package.business.image as a nested object {name, tag, full_name}"
      run_pkg_image_obj() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        read_package_business_json "image"
      }
      When call run_pkg_image_obj
      The output should equal '{"name":"registry.example.com/myapp","tag":"1.0.0","full_name":"registry.example.com/myapp:1.0.0"}'
    End

    It "records package.business.registry parsed from the image reference"
      run_pkg_registry() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        read_package_business_json "registry"
      }
      When call run_pkg_registry
      The output should equal '{"host":"registry.example.com","namespace":"","repository":"myapp"}'
    End

    It "records package.tech.build_duration_ms"
      run_pkg_build_duration() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        read_package_tech "build_duration_ms"
      }
      When call run_pkg_build_duration
      The output should match pattern "[0-9]*"
    End

    It "records package.business.image.digest from docker inspect RepoDigests"
      run_pkg_digest() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        docker() {
          if [[ "$1" == "inspect" ]]; then
            printf 'registry.example.com/myapp@sha256:abc123def4567890abc123def4567890abc123def4567890abc123def4567890\n'
            return 0
          fi
          return 0
        }
        export -f docker
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        unset -f docker
        jq -r '.stages[] | select(.name == "package") | .business.image.digest // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_pkg_digest
      The output should equal "sha256:abc123def4567890abc123def4567890abc123def4567890abc123def4567890"
    End

    It "omits package.business.image.digest when docker inspect has no RepoDigests"
      run_pkg_no_digest() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        docker() {
          if [[ "$1" == "inspect" ]]; then
            return 1
          fi
          return 0
        }
        export -f docker
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
        unset -f docker
        jq -r '.stages[] | select(.name == "package") | .business.image | has("digest")' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_pkg_no_digest
      The output should equal "false"
    End
  End

  Describe "registry parsing edge cases"
    parse_registry() {
      cat > "$BRIK_CONFIG_FILE" <<YAML
version: 1
project:
  name: test
  stack: node
package:
  docker:
    image: ${1}
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.docker.build() { return 0; }
      local ctx
      ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
      stages.package "$ctx" >/dev/null 2>&1
      read_package_business_json "registry"
    }

    It "parses registry/namespace/repository from a 3-segment image"
      When call parse_registry "ghcr.io/getbrik/brik-runner-node"
      The output should equal '{"host":"ghcr.io","namespace":"getbrik","repository":"brik-runner-node"}'
    End

    It "parses host/repository when no namespace is present"
      When call parse_registry "registry.example.com/myapp"
      The output should equal '{"host":"registry.example.com","namespace":"","repository":"myapp"}'
    End

    It "treats Docker Hub style user/image (no host dot) as namespace+repo"
      When call parse_registry "library/redis"
      The output should equal '{"host":"docker.io","namespace":"library","repository":"redis"}'
    End

    It "treats a single-segment image as docker.io/library/<image>"
      When call parse_registry "redis"
      The output should equal '{"host":"docker.io","namespace":"library","repository":"redis"}'
    End

    It "preserves :port in the host when the image is configured with a port"
      When call parse_registry "nexus.briklab.test:8082/brik/node-complete"
      The output should equal '{"host":"nexus.briklab.test:8082","namespace":"brik","repository":"node-complete"}'
    End
  End

  It "records status skipped in the pipeline report when no docker image"
    run_package_skip() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
      stages.package "$ctx" >/dev/null 2>&1 || return $?
      read_package_status
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

    It "returns 0 when stacks.docker.build succeeds"
      run_package_success() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
      }
      When call run_package_success
      The status should be success
    End

    It "returns non-zero when build fails"
      run_package_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" >/dev/null 2>&1
      }
      When call run_package_fail
      The status should equal 1
    End

    It "passes docker arguments to stacks.docker.build"
      run_package_args() {
        brik.use() { :; }
        stacks.docker.build() { printf '%s ' "$@"; printf '\n'; return 0; }
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
        stacks.docker.build() { return 0; }
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.docker.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}docker "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_docker
      The output should include "docker"
    End

    It "sets failed when docker publish fails"
      run_publish_docker_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.docker.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_docker_fail
      The status should equal 1
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.npm.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}npm "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_npm
      The output should include "npm"
    End

    It "sets failed when npm publish fails"
      run_publish_npm_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.npm.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_npm_fail
      The status should equal 1
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.maven.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}maven "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_maven
      The output should include "maven"
    End

    It "sets failed when maven publish fails"
      run_publish_maven_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.maven.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_maven_fail
      The status should equal 1
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.pypi.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}pypi "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_pypi
      The output should include "pypi"
    End

    It "sets failed when pypi publish fails"
      run_publish_pypi_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.pypi.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_pypi_fail
      The status should equal 1
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.cargo.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}cargo "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_cargo
      The output should include "cargo"
    End

    It "sets failed when cargo publish fails"
      run_publish_cargo_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.cargo.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_cargo_fail
      The status should equal 1
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
    token_var: NUGET_API_KEY
    source: https://nexus.example.com/repository/nuget-hosted/
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_publish_nuget'

    It "publishes nuget package after build"
      run_publish_nuget() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.nuget.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}nuget "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_nuget
      The output should include "nuget"
    End

    It "sets failed when nuget publish fails"
      run_publish_nuget_fail() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        pkg.nuget.publish() { return 1; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
      }
      When call run_publish_nuget_fail
      The status should equal 1
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
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.docker.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}docker "; return 0; }
        pkg.npm.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}npm "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_multi
      The output should include "docker"
      The output should include "npm"
    End

    It "stops on first publish failure (fail-fast)"
      run_publish_failfast() {
        brik.use() { :; }
        stacks.docker.build() { return 0; }
        local PUBLISH_CALLS=""
        pkg.docker.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}docker "; return 1; }
        pkg.npm.publish() { PUBLISH_CALLS="${PUBLISH_CALLS}npm "; return 0; }
        local ctx
        ctx="$(context.create "package")" 2>/dev/null || ctx="$(mktemp)"
        stages.package "$ctx" 2>/dev/null || true
        printf '%s' "$PUBLISH_CALLS"
      }
      When call run_publish_failfast
      The output should include "docker"
      The output should not include "npm"
    End
  End
End
