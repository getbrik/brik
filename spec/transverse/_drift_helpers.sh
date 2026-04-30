#!/usr/bin/env bash
# _drift_helpers.sh - Schema-runtime drift detection helpers
#
# Three exported functions:
#   drift.walk_leaves <schema_path>  - walk JSON Schema and emit one dot-path per leaf
#   drift.derive_envvar <dot_path>   - derive expected BRIK_* env var name/pattern
#   drift.has_consumer <dot_path> <lib_dir> - check if a consumer exists in lib/
#
# Loaded via source from config_schema_drift_spec.sh.

# drift.walk_leaves <schema_path>
# Outputs one dot-path per leaf (sorted, deduped). Resolves $ref, walks
# properties, additionalProperties objects, and array items objects.
# Treats string/integer/boolean/number/enum/const fields as leaves.
drift.walk_leaves() {
  local schema_path="$1"
  if [[ -z "$schema_path" || ! -f "$schema_path" ]]; then
    printf 'drift.walk_leaves: schema file not found: %s\n' "$schema_path" >&2
    return 1
  fi

  jq -r '
    . as $root |
    ($root["$defs"] // {}) as $defs |

    # Resolve a $ref string of the form "#/$defs/X" to the actual def schema.
    # Uses . as the ref string input (single-arg form avoids jq 1.6 scoping issues).
    def resolve_ref:
      . as $r | ($defs[ $r | ltrimstr("#/$defs/") ]) // {};

    # True if the current node is a scalar leaf with no child properties.
    def is_scalar:
      (type == "object") and (
        has("enum") or has("const") or
        (
          has("type") and
          (.type | (. == "string" or . == "integer" or . == "boolean" or . == "number")) and
          (has("properties") | not) and
          (has("additionalProperties") | not) and
          (has("items") | not)
        )
      );

    # Walk the schema tree rooted at . building dot-paths via the path argument.
    # Single-arg recursion (path string accumulator) avoids jq 1.6 two-arg
    # scoping issues where node argument would shadow outer bindings.
    def walk(path):
      if type != "object" then
        # Primitive JSON value at top level - emit path as leaf
        path
      elif has("$ref") then
        # Resolve $ref and continue walking the resolved schema
        .["$ref"] | resolve_ref | walk(path)
      elif is_scalar then
        # Leaf node: emit the accumulated path
        path
      elif has("properties") then
        # Object with named properties: recurse into each, capturing key first
        .properties | to_entries[] | (.key as $k | .value | walk(path + "." + $k))
      elif has("additionalProperties") and
           ((.additionalProperties | type) == "object") and
           ((.additionalProperties | has("type")) or
            (.additionalProperties | has("$ref")) or
            (.additionalProperties | has("properties"))) then
        # Wildcard object: use <key> placeholder and recurse into value schema
        .additionalProperties | walk(path + ".<key>")
      elif has("items") and
           ((.items | type) == "object") and
           ((.items | has("properties")) or
            (.items | has("$ref")) or
            (.items | has("type") and .items.type == "object")) then
        # Array with object-typed items: recurse with [] segment
        .items | walk(path + "[]")
      else
        # No recognisable child structure - emit path as opaque leaf
        if path != "" then path else empty end
      end;

    walk("") | select(. != "")
  ' "$schema_path" 2>/dev/null | sort -u
}

# drift.derive_envvar <dot_path>
# Returns the expected BRIK_* env var name or regex pattern.
# Standard rules:
#   - Drop leading "."
#   - Replace "." with "_", uppercase each segment
#   - "<key>" segments become the regex [A-Z][A-Z0-9_]*
#   - "[]" segments are omitted (array items share the parent var)
# Documented exceptions (verified against lib/transverse/config.sh):
#   Exception 1: .quality.lint.enabled -> BRIK_LINT_ENABLED
#     (abbreviated: "quality" prefix is dropped by convention)
#   Exception 2: .hooks.pre_*/.hooks.post_* -> BRIK_HOOK_PRE_*/BRIK_HOOK_POST_*
#     ("hooks" plural becomes "hook" singular)
#   Exception 3: .deploy.environments.<key>.<field> -> BRIK_DEPLOY_[A-Z][A-Z0-9_]*_<FIELD>
#     ("environments" segment is dropped: BRIK_DEPLOY_<ENV>_<FIELD> is the real pattern)
drift.derive_envvar() {
  local path="$1"

  # Exception 1: quality.lint.enabled is exported as BRIK_LINT_ENABLED
  if [[ "$path" == ".quality.lint.enabled" ]]; then
    printf 'BRIK_LINT_ENABLED'
    return 0
  fi

  # Exception 2: hooks.<stage> keys use singular HOOK (not HOOKS)
  if [[ "$path" == .hooks.* ]]; then
    local suffix="${path#.hooks.}"
    local upper_suffix
    upper_suffix="$(printf '%s' "$suffix" | tr '[:lower:]' '[:upper:]')"
    printf 'BRIK_HOOK_%s' "$upper_suffix"
    return 0
  fi

  # Exception 3: deploy.environments.<key>.<field> drops the "environments" segment
  # Real pattern: BRIK_DEPLOY_<ENV>_<FIELD> (not BRIK_DEPLOY_ENVIRONMENTS_<ENV>_<FIELD>)
  # Note: angle brackets in the glob must be quoted to avoid shell redirection errors.
  if [[ "$path" == ".deploy.environments.<key>."* ]]; then
    local field_suffix="${path#.deploy.environments."<key>".}"
    local upper_field
    upper_field="$(printf '%s' "$field_suffix" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    printf 'BRIK_DEPLOY_[A-Z][A-Z0-9_]*_%s' "$upper_field"
    return 0
  fi

  # Standard rule: drop leading ".", replace "." with "_", uppercase
  # "<key>" segments become regex [A-Z][A-Z0-9_]*, "[]" segments are omitted
  local stripped="${path#.}"
  local IFS='.'
  local segments
  read -ra segments <<< "$stripped"
  unset IFS

  local out=""
  for seg in "${segments[@]}"; do
    if [[ "$seg" == "<key>" ]]; then
      out="${out}_[A-Z][A-Z0-9_]*"
    elif [[ "$seg" == "[]" ]]; then
      # omit [] segments - array items share the parent var name
      :
    else
      local useg
      useg="$(printf '%s' "$seg" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
      if [[ -z "$out" ]]; then
        out="BRIK_${useg}"
      else
        out="${out}_${useg}"
      fi
    fi
  done

  printf '%s' "$out"
}

# drift.has_consumer <dot_path> <lib_dir>
# Returns 0 if a runtime consumer exists in lib_dir for the given schema path.
# Four detection strategies:
#   1. Path-based: search for config.get calls with the literal dot-path
#   2. Env-var-based: search for the derived BRIK_* variable name
#   3. Parent-path: for <key> wildcard leaves, check if the parent object path
#      is consumed as a whole (e.g. build_args object read without iterating keys)
#   4. Dynamic exports: hooks use export "BRIK_HOOK_PRE_${stage}" (constructed at
#      runtime) - detect by checking for the generic prefix in lib/
# Returns 1 if none of the strategies finds a consumer.
drift.has_consumer() {
  local dot_path="$1"
  local lib_dir="$2"

  if [[ -z "$lib_dir" || ! -d "$lib_dir" ]]; then
    return 1
  fi

  # Strategy 1: path-based grep for config.get '<dot_path>'
  # Build a regex: escape literal dots, map <key> to any unquoted key chars,
  # map [] to optional bracket notation.
  local path_regex
  path_regex="$(printf '%s' "$dot_path" | \
    sed \
      -e 's/\./\\./g' \
      -e 's/<key>/[^."'"'"']+/g' \
      -e 's/\[\]/([[][0-9]*[]])?/g' \
  )"

  if grep -qrE "config\.get ['\"]${path_regex}['\"]" "$lib_dir" 2>/dev/null; then
    return 0
  fi

  # Strategy 2: env-var-based grep for the BRIK_* variable name
  local envvar_pattern
  envvar_pattern="$(drift.derive_envvar "$dot_path")"

  if [[ "$envvar_pattern" == *'['* ]]; then
    # Pattern contains regex wildcards from <key> segments: use extended grep
    if grep -qrE "(export |)['\"]?${envvar_pattern}['\"]?" "$lib_dir" 2>/dev/null; then
      return 0
    fi
  else
    if grep -qr "$envvar_pattern" "$lib_dir" 2>/dev/null; then
      return 0
    fi
  fi

  # Strategy 3: for <key> wildcard leaves, check if the parent path is consumed
  # as an object (the runtime reads the whole object, not individual keys).
  if [[ "$dot_path" == *".<key>" ]]; then
    local parent_path="${dot_path%.<key>}"
    local parent_regex
    parent_regex="$(printf '%s' "$parent_path" | \
      sed \
        -e 's/\./\\./g' \
        -e 's/<key>/[^."'"'"']+/g' \
    )"
    if grep -qrE "config\.get ['\"]${parent_regex}['\"]" "$lib_dir" 2>/dev/null; then
      return 0
    fi
    # Also check parent env var name
    local parent_envvar
    parent_envvar="$(drift.derive_envvar "$parent_path")"
    if [[ "$parent_envvar" == *'['* ]]; then
      grep -qrE "(export |)['\"]?${parent_envvar}['\"]?" "$lib_dir" 2>/dev/null && return 0
    else
      grep -qr "$parent_envvar" "$lib_dir" 2>/dev/null && return 0
    fi
  fi

  # Strategy 4: dynamic export patterns for hooks.
  # Hooks are exported as: export "BRIK_HOOK_PRE_${upper_stage}=$val"
  # The variable name is constructed at runtime so literal grep fails.
  # Detect by checking for the generic prefix present in lib/transverse/config.sh.
  if [[ "$dot_path" == .hooks.pre_* ]]; then
    grep -qrE 'BRIK_HOOK_PRE_' "$lib_dir" 2>/dev/null && return 0
  fi
  if [[ "$dot_path" == .hooks.post_* ]]; then
    grep -qrE 'BRIK_HOOK_POST_' "$lib_dir" 2>/dev/null && return 0
  fi

  return 1
}
