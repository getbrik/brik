#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings
# @requires jq, transverse.sarif
# @description Unified findings management public API (facade). Provides the
#   ingest -> apply policy -> aggregate -> merge pipeline that every
#   stage producing findings (lint, sast, scan/*, container_scan, ...)
#   plugs into. SARIF 2.1.0 is the pivot format; non-SARIF tools
#   converge through converters/ (P5).
#
#   Public surface (unchanged; implementation split into findings/):
#     - findings.from_sarif    : validate a tool's SARIF report.       [ingest]
#     - findings.from_json     : convert a non-SARIF output to SARIF.   [ingest]
#     - findings.apply_policy  : preset + org allowlist annotation.     [policy]
#     - findings.expiring_soon : allowlist entries expiring soon.       [policy]
#     - findings.aggregate     : record business.findings + report.  [aggregate]
#     - findings.merge_pipeline: pipeline-level SARIF aggregate.      [aggregate]
#     - findings.process       : ingest -> policy -> aggregate.          [gate]
#     - findings.scan_gate     : verify-scan gate composition.           [gate]
#     - findings.gate          : pass/fail from failing count.           [gate]
#
# This file is a thin facade: it owns the shared dependencies, the canonical
# jq result-severity library (used by both apply_policy and the aggregate
# v2-stats program), and sources the implementation modules. Consumers still
# `brik.use transverse.findings` (or Include findings.sh) and call findings.*
# exactly as before.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED=1

# Source the SARIF helpers when the host has not loaded them already.
# Keeping this defensive lets callers Include findings.sh in isolation
# (e.g. unit tests) without forcing them to know the dependency order.
if [[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]]; then
    if [[ -f "${BASH_SOURCE[0]%/*}/sarif.sh" ]]; then
        # shellcheck source=sarif.sh
        . "${BASH_SOURCE[0]%/*}/sarif.sh"
    fi
fi

# Source the fix-exists classifier so findings.process can annotate the
# SARIF before apply_policy. Defensive, same pattern as sarif.sh above.
if [[ -z "${_BRIK_FIX_CLASSIFIER_LOADED:-}" ]]; then
    if [[ -f "${BASH_SOURCE[0]%/*}/fix_classifier.sh" ]]; then
        # shellcheck source=fix_classifier.sh
        . "${BASH_SOURCE[0]%/*}/fix_classifier.sh"
    fi
fi

# Canonical jq helpers for SARIF result -> severity resolution, shared by the
# apply_policy (findings/policy.sh) and v2-stats (findings/aggregate.sh) jq
# programs (previously copy-pasted into both). Depends on cvss_bucket /
# level_bucket from ${_BRIK_JQ_SEVERITY_DEFS} (transverse/sarif.sh), so
# prepend both, severity defs first:
#   jq ... "${_BRIK_JQ_SEVERITY_DEFS}${_FINDINGS_JQ_RESULT_DEFS}"' ...rest... '
# Defined here (before the implementation modules are sourced) so it is a
# facade-owned global the policy and aggregate modules can reference.
# KCOV_EXCL_START -- jq function library, not bash code
_FINDINGS_JQ_RESULT_DEFS=$(cat <<'JQ'
def rule_for($r; $sarif):
  ($r.ruleId // null) as $rid
  | if $rid == null then null
    else
      (($sarif.runs[0].tool.driver.rules // [])[]?
       | select(.id == $rid))
      // null
    end;
def severity_of_result($r; $sarif):
  rule_for($r; $sarif) as $rule
  | ($r.properties["security-severity"]
     // ($rule.properties["security-severity"] // null)) as $cvss
  | if   $cvss != null            then cvss_bucket($cvss)
    elif ($r.level // null) != null then level_bucket($r.level)
    elif ($rule.defaultConfiguration.level // null) != null
                                    then level_bucket($rule.defaultConfiguration.level)
    else "info" end;
JQ
)
# KCOV_EXCL_STOP

# Source the implementation modules. Order is not behaviourally significant
# (Bash resolves function names at call time), but follows the pipeline
# direction: ingest, policy, aggregate, then the gate/orchestration layer.
# shellcheck source=findings/ingest.sh
. "${BASH_SOURCE[0]%/*}/findings/ingest.sh"
# shellcheck source=findings/policy.sh
. "${BASH_SOURCE[0]%/*}/findings/policy.sh"
# shellcheck source=findings/aggregate.sh
. "${BASH_SOURCE[0]%/*}/findings/aggregate.sh"
# shellcheck source=findings/gate.sh
. "${BASH_SOURCE[0]%/*}/findings/gate.sh"
