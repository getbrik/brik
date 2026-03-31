#!/usr/bin/env bash
# @module condition-eval
# @description Evaluates simple condition expressions from brik.yml deploy environments.
#
# Supported expressions:
#   branch == 'main'        - exact branch match against CI_COMMIT_BRANCH
#   branch == 'develop'     - exact branch match
#   tag =~ 'v*'             - glob match against CI_COMMIT_TAG
#   tag == 'v1.0.0'         - exact tag match
#   manual                  - always false (requires manual trigger)
#
# The grammar is intentionally minimal: equality (==) and glob match (=~).

# Guard against double-sourcing
[[ -n "${_BRIK_CONDITION_EVAL_LOADED:-}" ]] && return 0
_BRIK_CONDITION_EVAL_LOADED=1

# Evaluate a condition expression.
# Usage: condition.eval <expression>
# Returns 0 (true) or 1 (false).
#
# Examples:
#   condition.eval "branch == 'main'"
#   condition.eval "tag =~ 'v*'"
#   condition.eval "manual"
condition.eval() {
    local expression="$1"

    # Trim whitespace
    expression="$(echo "$expression" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ -z "$expression" ]]; then
        echo "error: empty condition expression" >&2
        return 1
    fi

    # Special keyword: manual
    if [[ "$expression" == "manual" ]]; then
        # Manual stages are not auto-triggered
        return 1
    fi

    # Parse the expression: <subject> <operator> <value>
    local subject operator value

    if [[ "$expression" =~ ^([a-zA-Z_]+)[[:space:]]+(==|=~)[[:space:]]+\'([^\']*)\' ]]; then
        subject="${BASH_REMATCH[1]}"
        operator="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"
    elif [[ "$expression" =~ ^([a-zA-Z_]+)[[:space:]]+(==|=~)[[:space:]]+\"([^\"]*)\" ]]; then
        subject="${BASH_REMATCH[1]}"
        operator="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"
    else
        echo "error: invalid condition expression: $expression" >&2
        echo "hint: expected format: subject == 'value' or subject =~ 'pattern'" >&2
        return 1
    fi

    # Resolve the subject to an actual value
    local actual_value
    actual_value="$(_condition.resolve_subject "$subject")"

    # Evaluate the operator
    case "$operator" in
        '==')
            [[ "$actual_value" == "$value" ]]
            return $?
            ;;
        '=~')
            # Glob match (not regex)
            # shellcheck disable=SC2254
            case "$actual_value" in
                $value) return 0 ;;
                *)      return 1 ;;
            esac
            ;;
        *)
            echo "error: unsupported operator: $operator" >&2
            return 1
            ;;
    esac
}

# Resolve a condition subject to its actual value from CI environment variables.
# Usage: _condition.resolve_subject <subject>
_condition.resolve_subject() {
    local subject="$1"

    case "$subject" in
        branch)
            printf '%s' "${CI_COMMIT_BRANCH:-${GITHUB_REF_NAME:-${GIT_BRANCH:-}}}"
            ;;
        tag)
            printf '%s' "${CI_COMMIT_TAG:-${GITHUB_REF_NAME:-${GIT_TAG:-}}}"
            ;;
        pipeline_source)
            printf '%s' "${CI_PIPELINE_SOURCE:-}"
            ;;
        merge_request)
            printf '%s' "${CI_MERGE_REQUEST_IID:-}"
            ;;
        *)
            # Try as a raw environment variable name
            local var_value="${!subject:-}"
            printf '%s' "$var_value"
            ;;
    esac
}

# Evaluate deploy conditions for a specific environment.
# Reads the condition from brik.yml deploy.environments.<env>.when
# Usage: condition.eval_deploy_env <env_name>
# Requires: config-reader.sh to be sourced and BRIK_CONFIG_FILE to be set.
condition.eval_deploy_env() {
    local env_name="$1"

    if ! command -v config.get >/dev/null 2>&1; then
        echo "error: config-reader.sh must be sourced before condition-eval.sh" >&2
        return 1
    fi

    local when_expr
    when_expr="$(config.get ".deploy.environments.${env_name}.when" '')"

    if [[ -z "$when_expr" ]]; then
        echo "warning: no condition defined for environment: $env_name" >&2
        return 1
    fi

    condition.eval "$when_expr"
    return $?
}
