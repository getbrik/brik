#!/usr/bin/env bash
# @module version-info
# @description Single source of truth for Brik version metadata.
#
# Sourced by the runtime bootstrap and by bin/brik.
# Other modules should NEVER hardcode BRIK_VERSION.

# Guard against double-sourcing
[[ -n "${_BRIK_VERSION_INFO_LOADED:-}" ]] && return 0
_BRIK_VERSION_INFO_LOADED=1

export BRIK_VERSION="0.2.0"
export BRIK_SCHEMA_VERSION="v1"
export BRIK_RUNTIME="bash"
export BRIK_REF="v${BRIK_VERSION}"
