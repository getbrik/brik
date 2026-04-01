#!/usr/bin/env bash
# @module stages/notify
# @description Notify stage - pipeline summary.

# Notify stage: print pipeline summary.
# Usage: stages.notify <context_file>
stages.notify() {
    # shellcheck disable=SC2034
    local context_file="$1"

    log.info "notify stage - pipeline summary"

    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"

    echo "========================================"
    echo "  Brik Pipeline Summary"
    echo "========================================"
    echo "  Project : $project_name"
    echo "  Platform: ${BRIK_PLATFORM:-unknown}"
    echo "  Ref     : ${BRIK_COMMIT_REF:-unknown}"
    echo "  SHA     : ${BRIK_COMMIT_SHORT_SHA:-unknown}"
    echo "========================================"

    return 0
}
