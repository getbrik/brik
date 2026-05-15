Describe "stages.release"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/release.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    mock.workspace.setup
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="release-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID 2>/dev/null || true
  }

  read_release_new_version() {
    jq -r '.stages[] | select(.name == "release") | .business.new_version // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_release_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "release") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_release_business() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "release") | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.release >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 on success"
    run_release() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
    }
    When call run_release
    The status should be success
  End

  It "records new_version in the pipeline report business section"
    run_release_check() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      local version
      version="$(read_release_new_version)"
      if [[ -n "$version" ]]; then echo "has_version"; else echo "no_version"; fi
    }
    When call run_release_check
    The output should equal "has_version"
  End

  It "records release.tech.strategy"
    run_release_strategy_record() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      read_release_tech "strategy"
    }
    When call run_release_strategy_record
    The output should equal "semver"
  End

  It "records release.tech.tag_prefix"
    run_release_prefix_record() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      read_release_tech "tag_prefix"
    }
    When call run_release_prefix_record
    The output should equal "v"
  End

  It "records release.tech.dry_run as JSON boolean false by default"
    run_release_dryrun_record() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      jq -c '.stages[] | select(.name == "release") | .tech.dry_run' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_release_dryrun_record
    The output should equal "false"
  End

  It "records release.tech.dry_run as JSON boolean true when BRIK_DRY_RUN=true"
    run_release_dryrun_true() {
      export BRIK_DRY_RUN="true"
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      jq -c '.stages[] | select(.name == "release") | .tech.dry_run' \
        "$BRIK_LOG_DIR/aggregate-report.json"
      unset BRIK_DRY_RUN
    }
    When call run_release_dryrun_true
    The output should equal "true"
  End

  It "records release.business.previous_version and new_version equal when no bump engine"
    run_release_versions() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      local prev new
      prev="$(read_release_business 'previous_version')"
      new="$(read_release_business 'new_version')"
      [[ -n "$prev" && "$prev" == "$new" ]] && echo "equal" || echo "diff:$prev|$new"
    }
    When call run_release_versions
    The output should equal "equal"
  End

  It "records release.business.bump_type as 'none' without BRIK_TAG"
    run_release_bump_none() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      read_release_business "bump_type"
    }
    When call run_release_bump_none
    The output should equal "none"
  End

  It "exports BRIK_RELEASE_STRATEGY from config"
    run_release_strategy() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_RELEASE_STRATEGY:-}"
    }
    When call run_release_strategy
    The output should equal "semver"
  End

  It "exports BRIK_RELEASE_TAG_PREFIX from config"
    run_release_prefix() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"
    }
    When call run_release_prefix
    The output should equal "v"
  End

  # Cross-stage env publishing (chantier env-channels-unification).
  # release computes BRIK_APP_VERSION and publishes it through the env section
  # of the report backend so package and downstream stages can read it
  # (formerly written via pipeline.env.set, now via report.record env).
  It "records BRIK_APP_VERSION into report.env"
    run_release_records_env_version() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1 || return $?
      jq -r '.stages[] | select(.name == "release") | .env.BRIK_APP_VERSION // empty' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_release_records_env_version
    The output should not equal ""
  End

  It "projects BRIK_APP_VERSION into pipeline.env via the post-stage hook"
    run_release_projects_version() {
      local ctx
      ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
      stages.release "$ctx" >/dev/null 2>&1 || return $?
      _stage.run._project_env "release" >/dev/null 2>&1 || true
      grep -c '^BRIK_APP_VERSION=' "$BRIK_PIPELINE_ENV"
    }
    When call run_release_projects_version
    The output should equal "1"
  End

  Describe "with custom release config"
    setup_release() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
release:
  strategy: calver
  tag_prefix: release-
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_release'

    It "uses custom strategy and prefix"
      run_release_custom() {
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx"
      }
      When call run_release_custom
      The error should include "release strategy: calver"
      The error should include "tag prefix: release-"
    End
  End

  Describe "with BRIK_TAG set (release trigger)"
    setup_tag() {
      export BRIK_TAG="v1.2.3"
      # Set up a git repo so version.current works
      TEST_GIT="$(mktemp -d)"
      ORIG_DIR="$(pwd)"
      cd "$TEST_GIT" || return 1
      git init -q
      git config user.email "test@test.com"
      git config user.name "Test"
      printf 'init\n' > README.md
      git add README.md && git commit -q -m "chore: init"
      git tag v1.2.3
      export BRIK_WORKSPACE="$TEST_GIT"
      export BRIK_PROJECT_DIR="$TEST_GIT"
    }
    cleanup_tag() {
      cd "$ORIG_DIR" || true
      unset BRIK_TAG
      rm -rf "$TEST_GIT"
    }
    Before 'setup_tag'
    After 'cleanup_tag'

    It "handles release trigger with BRIK_TAG"
      run_release_tag() {
        _stages.release._prepare()  { return 0; }
        _stages.release._finalize() { return 0; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" 2>/dev/null
      }
      When call run_release_tag
      The status should be success
    End

    It "records release.business.bump_type as 'explicit' when BRIK_TAG is set"
      run_release_bump_explicit() {
        _stages.release._prepare()  { return 0; }
        _stages.release._finalize() { return 0; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        read_release_business "bump_type"
      }
      When call run_release_bump_explicit
      The output should equal "explicit"
    End

    It "records release.business.tag as a nested object on dry-run finalize"
      run_release_tag_object() {
        export BRIK_DRY_RUN="true"
        _stages.release._prepare() { return 0; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        jq -c '.stages[] | select(.name == "release") | .business.tag | {name, dry_run}' \
          "$BRIK_LOG_DIR/aggregate-report.json"
        unset BRIK_DRY_RUN
      }
      When call run_release_tag_object
      The output should equal '{"name":"v1.2.3","dry_run":true}'
    End

    It "handles changelog disabled"
      run_release_no_changelog() {
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        _stages.release._prepare()  { return 0; }
        _stages.release._finalize() { return 0; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" 2>/dev/null
      }
      When call run_release_no_changelog
      The status should be success
    End

    It "passes changelog file when configured"
      run_release_changelog_file() {
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        export BRIK_RELEASE_CHANGELOG_FILE="CHANGES.md"
        _stages.release._prepare()  { return 0; }
        _stages.release._finalize() { return 0; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" 2>/dev/null
      }
      When call run_release_changelog_file
      The status should be success
    End

    It "logs dry-run branches in _prepare when BRIK_DRY_RUN=true"
      run_release_dryrun() {
        export BRIK_DRY_RUN="true"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx"
        unset BRIK_DRY_RUN
      }
      When call run_release_dryrun
      The error should include "[dry-run]"
      The error should include "release prepared (dry-run)"
    End

    It "propagates _prepare failure as the stage exit code"
      run_release_prepare_fail() {
        _stages.release._prepare() { return 5; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" 2>/dev/null
      }
      When call run_release_prepare_fail
      The status should equal 5
    End

    It "propagates _finalize failure as the stage exit code"
      run_release_finalize_fail() {
        _stages.release._prepare()  { return 0; }
        _stages.release._finalize() { return 5; }
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" 2>/dev/null
      }
      When call run_release_finalize_fail
      The status should equal 5
    End
  End

  Describe "_stages.release._prepare"
    setup_prepare() {
      PREP_WS="$(mktemp -d)"
      export BRIK_WORKSPACE="$PREP_WS"
      ORIG_DIR="$(pwd)"
      cd "$PREP_WS" || return 1
    }
    cleanup_prepare() {
      cd "$ORIG_DIR" || true
      rm -rf "$PREP_WS"
      unset BRIK_DRY_RUN BRIK_RELEASE_CHANGELOG_ENABLED BRIK_RELEASE_CHANGELOG_FILE
    }
    Before 'setup_prepare'
    After 'cleanup_prepare'

    It "dry-run emits all expected log lines"
      run_prep_dryrun() {
        export BRIK_DRY_RUN="true"
        _stages.release._prepare "1.0.0"
      }
      When call run_prep_dryrun
      The status should be success
      The error should include "[dry-run] changelog.generate"
      The error should include "[dry-run] patch package.json"
      The error should include "[dry-run] git add -A + commit"
    End

    It "dry-run with changelog disabled skips changelog log"
      run_prep_no_cl() {
        export BRIK_DRY_RUN="true"
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        _stages.release._prepare "1.0.0"
      }
      When call run_prep_no_cl
      The status should be success
      The error should not include "changelog.generate"
      The error should include "[dry-run] patch package.json"
    End

    It "writes a new changelog when file does not exist"
      run_prep_new_cl() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        brik.use() { :; }
        changelog.generate() { printf 'feat: thing'; return 0; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.2.3"
        cat "${BRIK_WORKSPACE}/CHANGELOG.md" 2>/dev/null
      }
      When call run_prep_new_cl
      The status should be success
      The output should include "# 1.2.3"
      The output should include "feat: thing"
    End

    It "prepends to an existing changelog"
      run_prep_existing_cl() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        printf 'previous\n' > "${BRIK_WORKSPACE}/CHANGELOG.md"
        brik.use() { :; }
        changelog.generate() { printf 'feat: another'; return 0; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "2.0.0"
        cat "${BRIK_WORKSPACE}/CHANGELOG.md"
      }
      When call run_prep_existing_cl
      The status should be success
      The output should include "# 2.0.0"
      The output should include "feat: another"
      The output should include "previous"
    End

    It "patches package.json version when present"
      run_prep_pkg_json() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        printf '{"name":"p","version":"0.0.0"}\n' > "${BRIK_WORKSPACE}/package.json"
        brik.use() { :; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "3.1.4"
        jq -r .version "${BRIK_WORKSPACE}/package.json"
      }
      When call run_prep_pkg_json
      The status should be success
      The output should equal "3.1.4"
    End

    It "returns EXTERNAL_FAIL when git commit_all fails"
      run_prep_commit_fail() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        brik.use() { :; }
        transverse.git.config_identity() { :; }
        transverse.git.commit_all() { return 1; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare "1.0.0"
        printf '%s' "$?"
      }
      When call run_prep_commit_fail
      The output should equal "5"
    End

    It "calls transverse.git.config_identity before commit_all"
      run_prep_identity() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        ORDER=""
        brik.use() { :; }
        transverse.git.config_identity() { ORDER="${ORDER}identity,"; return 0; }
        transverse.git.commit_all() { ORDER="${ORDER}commit,"; return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.0.0"
        printf '%s' "$ORDER"
      }
      When call run_prep_identity
      The output should equal "identity,commit,"
    End

    It "records release.business.changelog.path when changelog is generated"
      run_prep_changelog_path() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        export BRIK_RELEASE_CHANGELOG_FILE="CHANGELOG.md"
        brik.use() { :; }
        changelog.generate() { printf '## Changes\n\n### Features\n\n- a (1)\n- b (2)\n'; return 0; }
        changelog.count_entries() { printf '2'; return 0; }
        transverse.git.config_identity() { :; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.0.0"
        jq -r '.stages[] | select(.name == "release") | .business.changelog.path // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_prep_changelog_path
      The output should end with "/CHANGELOG.md"
    End

    It "records release.business.changelog.entries_count from changelog.count_entries"
      run_prep_changelog_count() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        brik.use() { :; }
        changelog.generate() { printf '## Changes\n\n### Features\n\n- a\n- b\n- c\n'; return 0; }
        changelog.count_entries() { printf '3'; return 0; }
        transverse.git.config_identity() { :; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.0.0"
        jq -r '.stages[] | select(.name == "release") | .business.changelog.entries_count // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_prep_changelog_count
      The output should equal "3"
    End

    It "records release.business.changelog.generated_at as ISO-8601"
      run_prep_changelog_ts() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="true"
        brik.use() { :; }
        changelog.generate() { printf '## Changes\n\n- a\n'; return 0; }
        changelog.count_entries() { printf '1'; return 0; }
        transverse.git.config_identity() { :; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.0.0"
        jq -r '.stages[] | select(.name == "release") | .business.changelog.generated_at // "<missing>"' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_prep_changelog_ts
      The output should match pattern '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*'
    End

    It "omits release.business.changelog when changelog is disabled"
      run_prep_no_changelog_record() {
        unset BRIK_DRY_RUN
        export BRIK_RELEASE_CHANGELOG_ENABLED="false"
        brik.use() { :; }
        transverse.git.config_identity() { :; }
        transverse.git.commit_all() { return 0; }
        pipeline.require_tool() { return 0; }
        _stages.release._prepare 2>/dev/null "1.0.0"
        jq -r '[.stages[] | select(.name == "release") | .business.changelog // null | select(. != null)] | length' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_prep_no_changelog_record
      The output should equal "0"
    End
  End

  Describe "_stages.release._finalize"
    It "calls git.tag with prefixed tag name and message"
      run_final() {
        local TAG_LOG=""
        git.tag() { TAG_LOG="$*"; return 0; }
        _stages.release._finalize 2>/dev/null "1.0.0" "v"
        printf '%s' "$TAG_LOG"
      }
      When call run_final
      The output should include "v1.0.0"
      The output should include "--message Release 1.0.0"
    End

    It "forwards --dry-run when BRIK_DRY_RUN=true"
      run_final_dryrun() {
        export BRIK_DRY_RUN="true"
        local TAG_LOG=""
        git.tag() { TAG_LOG="$*"; return 0; }
        _stages.release._finalize 2>/dev/null "2.0.0" "release-"
        unset BRIK_DRY_RUN
        printf '%s' "$TAG_LOG"
      }
      When call run_final_dryrun
      The output should include "--dry-run"
      The output should include "release-2.0.0"
    End

    It "propagates git.tag failure code"
      run_final_fail() {
        git.tag() { return 42; }
        _stages.release._finalize "1.0.0" "v"
        printf '%s' "$?"
      }
      When call run_final_fail
      The output should equal "42"
    End
  End
End
