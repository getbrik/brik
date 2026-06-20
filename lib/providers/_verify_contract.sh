#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module providers/_verify_contract
# @description Runtime contract introspection. At bind time,
# fail-closed, prove that a provider's module exposes every operation its
# capability contract requires.
#
# This is ADR-002 mechanism 2 (declare -f presence check) generalized from
# stage functions to provider operations: brik resolves
# provider -> module + contract, reads the contract's required_operations from
# the registry, and asserts `declare -f providers.<module>.<op>` for each one.
# A missing operation is a CONFIG_ERROR -- the provider must never be bound.
#
# STRICTLY PRESENCE-ONLY: this never invokes an operation and never asserts
# any behaviour (fail-closed vs best-effort, signature, side effects). Keeping
# it presence-only is what makes the framework nature-agnostic, so the single
# artifact-attestation pilot cannot freeze its own semantics into the
# framework. Unit obligations and behavioural conformance live elsewhere.

[[ -n "${_BRIK_PROVIDERS_VERIFY_CONTRACT_LOADED:-}" ]] && return 0
_BRIK_PROVIDERS_VERIFY_CONTRACT_LOADED=1

# Registry accessors (provider.module / .contract, contract.operations) come
# from the flat registry lib, sourced directly like the stack helpers do.
# shellcheck source=../registry/registry.sh
[[ -z "${_BRIK_REGISTRY_LOADED_API:-}" ]] && . "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

# providers.verify_contract <provider-id>
#
# Returns:
#   0                       every required operation is defined
#   BRIK_EXIT_INVALID_INPUT no provider id given
#   BRIK_EXIT_CONFIG_ERROR  unknown provider, no module declared, unknown
#                           contract, module unloadable, or a missing operation
providers.verify_contract() {
  local provider="${1:-}"
  if [[ -z "$provider" ]]; then
    log.error "providers.verify_contract: provider id required"
    return "$BRIK_EXIT_INVALID_INPUT"
  fi

  if ! registry.provider.exists "$provider"; then
    log.error "providers.verify_contract: unknown provider: ${provider}"
    return "$BRIK_EXIT_CONFIG_ERROR"
  fi

  local module contract
  module="$(registry.provider.module "$provider")" || return $?
  contract="$(registry.provider.contract "$provider")" || return $?

  if [[ -z "$module" ]]; then
    log.error "providers.verify_contract: provider ${provider} declares no module"
    return "$BRIK_EXIT_CONFIG_ERROR"
  fi
  if ! registry.contract.exists "$contract"; then
    log.error "providers.verify_contract: provider ${provider} references unknown contract: ${contract}"
    return "$BRIK_EXIT_CONFIG_ERROR"
  fi

  if ! brik.use "providers.${module}"; then
    log.error "providers.verify_contract: cannot load module providers.${module} for ${provider}"
    return "$BRIK_EXIT_CONFIG_ERROR"
  fi

  local op missing=0
  while IFS= read -r op; do
    [[ -z "$op" ]] && continue
    if ! declare -f "providers.${module}.${op}" >/dev/null 2>&1; then
      log.error "providers.verify_contract: ${provider} (${module}) missing required operation: ${op}"
      missing=$((missing + 1))
    fi
  done < <(registry.contract.operations "$contract")

  if [[ $missing -ne 0 ]]; then
    log.error "providers.verify_contract: ${provider} does not satisfy ${contract} (${missing} missing)"
    return "$BRIK_EXIT_CONFIG_ERROR"
  fi
  return 0
}
