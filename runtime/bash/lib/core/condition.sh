#!/usr/bin/env bash
# @module condition
# @description Evaluates simple condition expressions from brik.yml deploy environments.
#
# Portable condition evaluator for the Brik runtime.
# Loaded via: brik.use condition
#
# Uses normalized BRIK_* variables (see Spec 02, section 11).
#
# Supported expressions:
#   branch == 'main'        - exact branch match against BRIK_BRANCH
#   branch == 'develop'     - exact branch match
#   tag =~ 'v*'             - glob match against BRIK_TAG
#   tag == 'v1.0.0'         - exact tag match
#   manual                  - always false (requires manual trigger)
#
# The grammar is intentionally minimal: equality (==) and glob match (=~).

# Guard against double-sourcing (compatible with brik.use)
[[ -n "${_BRIK_MODULE_CONDITION_LOADED:-}" ]] && return 0
_BRIK_MODULE_CONDITION_LOADED=1

# Evaluate a condition expression.
# Usage: condition.eval <expression>
# Returns 0 (true) or 1 (false).
#
# Supports compound expressions with AND/OR operators:
#   Compound expressions: AND has higher precedence than OR.
#   OR is split first (lowest precedence), then each part checks for AND.
#   Evaluation is right-recursive: "A OR B OR C" -> A || (B || C)
#   "A AND B OR C" -> (A && B) || C
#   No parentheses support.
#
# Examples:
#   condition.eval "branch == 'main'"
#   condition.eval "tag =~ 'v*'"
#   condition.eval "manual"
#   condition.eval "branch == 'main' AND tag =~ 'v*'"
#   condition.eval "branch == 'main' OR branch == 'develop'"
#   condition.eval "branch == 'main' AND tag =~ 'v*' OR branch == 'develop'"
condition.eval() {
    local expression="$1"

    # Trim whitespace
    expression="$(echo "$expression" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ -z "$expression" ]]; then
        log.error "empty condition expression"
        return "$BRIK_EXIT_FAILURE"
    fi

    # Handle OR at top level (lowest precedence)
    # Split on first " OR " and evaluate left || right recursively
    if [[ "$expression" == *" OR "* ]]; then
        local or_left or_right
        or_left="${expression%% OR *}"
        or_right="${expression#* OR }"
        # Evaluate left part (which may contain AND)
        condition.eval "$or_left" && return 0
        # Evaluate right part (which may contain AND or OR)
        condition.eval "$or_right"
        return $?
    fi

    # Handle AND (higher precedence than OR)
    # Split on first " AND " and evaluate left && right recursively
    if [[ "$expression" == *" AND "* ]]; then
        local and_left and_right
        and_left="${expression%% AND *}"
        and_right="${expression#* AND }"
        # Both sides must be true
        condition.eval "$and_left" || return "$BRIK_EXIT_FAILURE"
        condition.eval "$and_right"
        return $?
    fi

    # Special keyword: manual
    if [[ "$expression" == "manual" ]]; then
        # Manual stages are not auto-triggered
        return "$BRIK_EXIT_FAILURE"
    fi

    # Parse the simple expression: <subject> <operator> <value>
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
        log.error "invalid condition expression: $expression"
        log.warn "expected format: subject == 'value' or subject =~ 'pattern'"
        return "$BRIK_EXIT_FAILURE"
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
                *)      return "$BRIK_EXIT_FAILURE" ;;
            esac
            ;;
        *)
            log.error "unsupported operator: $operator"
            return "$BRIK_EXIT_FAILURE"
            ;;
    esac
}

# Resolve a condition subject to its actual value from BRIK_* normalized variables.
# Usage: _condition.resolve_subject <subject>
_condition.resolve_subject() {
    local subject="$1"

    case "$subject" in
        branch)
            printf '%s' "${BRIK_BRANCH:-}"
            ;;
        tag)
            printf '%s' "${BRIK_TAG:-}"
            ;;
        pipeline_source)
            printf '%s' "${BRIK_PIPELINE_SOURCE:-}"
            ;;
        merge_request)
            printf '%s' "${BRIK_MERGE_REQUEST_ID:-}"
            ;;
        *)
            if [[ "$subject" == BRIK_* ]]; then
                local var_value="${!subject:-}"
                printf '%s' "$var_value"
            else
                log.warn "unsupported condition subject: $subject"
                printf ''
            fi
            ;;
    esac
}

# Evaluate deploy conditions for a specific environment.
# Reads the condition from brik.yml deploy.environments.<env>.when
# Usage: condition.eval_deploy_env <env_name>
# Requires: config module loaded (via brik.use config)
condition.eval_deploy_env() {
    local env_name="$1"

    # Lazy-load config module if not yet loaded
    if ! declare -f config.get >/dev/null 2>&1; then
        brik.use config || {
            log.error "config module is required for condition.eval_deploy_env"
            return "$BRIK_EXIT_FAILURE"
        }
    fi

    local when_expr
    when_expr="$(config.get ".deploy.environments.${env_name}.when" '')"

    if [[ -z "$when_expr" ]]; then
        log.warn "no condition defined for environment: $env_name"
        return "$BRIK_EXIT_FAILURE"
    fi

    condition.eval "$when_expr"
    return $?
}
