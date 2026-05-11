#!/usr/bin/env bash
# @module verify._cfg
# @description Project-config detection helpers shared by verify.lint and
# verify.format. Each helper returns 0 when the project has explicitly
# opted into a tool via a config file; 1 otherwise. The verify.* dispatchers
# call these to skip cleanly instead of running a tool with default rules
# the project never agreed to enforce.
#
# All helpers use bash builtins only (no grep/awk) so they keep working
# under PATH-isolated test environments.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_CFG_LOADED:-}" ]] && return 0
_BRIK_VERIFY_CFG_LOADED=1

# pyproject [tool.ruff], ruff.toml, or .ruff.toml.
_verify_cfg.has_ruff() {
    local ws="$1"
    [[ -f "${ws}/ruff.toml" || -f "${ws}/.ruff.toml" ]] && return 0
    [[ -f "${ws}/pyproject.toml" ]] || return 1
    local content
    content="$(<"${ws}/pyproject.toml")" || return 1
    [[ $'\n'"$content" =~ $'\n'\[tool\.ruff(\.|\]) ]]
}

# pyproject [tool.black] is the canonical black config marker.
_verify_cfg.has_black() {
    local ws="$1"
    [[ -f "${ws}/pyproject.toml" ]] || return 1
    local content
    content="$(<"${ws}/pyproject.toml")" || return 1
    [[ $'\n'"$content" =~ $'\n'\[tool\.black(\.|\]) ]]
}

# Root checkstyle.xml, maven-checkstyle-plugin in pom, or checkstyle reference
# in build.gradle / build.gradle.kts.
_verify_cfg.has_checkstyle() {
    local ws="$1"
    [[ -f "${ws}/checkstyle.xml" ]] && return 0
    local content
    if [[ -f "${ws}/pom.xml" ]]; then
        content="$(<"${ws}/pom.xml")" || return 1
        [[ "$content" == *maven-checkstyle-plugin* ]] && return 0
    fi
    local f
    for f in "${ws}/build.gradle" "${ws}/build.gradle.kts"; do
        [[ -f "$f" ]] || continue
        content="$(<"$f")" || continue
        [[ "$content" == *checkstyle* ]] && return 0
    done
    return 1
}

# dotnet format reads .editorconfig; without it it has nothing to enforce.
_verify_cfg.has_dotnet_format() {
    local ws="$1"
    [[ -f "${ws}/.editorconfig" ]]
}

# Prettier: any .prettierrc* / prettier.config.* file, or "prettier" key in package.json.
_verify_cfg.has_prettier() {
    local ws="$1"
    local f
    for f in .prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml \
             .prettierrc.json5 .prettierrc.js .prettierrc.cjs .prettierrc.mjs \
             .prettierrc.toml prettier.config.js prettier.config.cjs prettier.config.mjs; do
        [[ -f "${ws}/$f" ]] && return 0
    done
    [[ -f "${ws}/package.json" ]] || return 1
    local content
    content="$(<"${ws}/package.json")" || return 1
    [[ "$content" == *'"prettier"'* ]]
}

# Biome: biome.json or biome.jsonc.
_verify_cfg.has_biome() {
    local ws="$1"
    [[ -f "${ws}/biome.json" || -f "${ws}/biome.jsonc" ]]
}

# rustfmt: rustfmt.toml or .rustfmt.toml.
_verify_cfg.has_rustfmt() {
    local ws="$1"
    [[ -f "${ws}/rustfmt.toml" || -f "${ws}/.rustfmt.toml" ]]
}

# google-java-format: opt-in via spotless / fmt-maven-plugin in build files.
_verify_cfg.has_google_java_format() {
    local ws="$1"
    local content
    if [[ -f "${ws}/pom.xml" ]]; then
        content="$(<"${ws}/pom.xml")" || return 1
        [[ "$content" == *fmt-maven-plugin* || "$content" == *spotless-maven-plugin* ]] && return 0
    fi
    local f
    for f in "${ws}/build.gradle" "${ws}/build.gradle.kts"; do
        [[ -f "$f" ]] || continue
        content="$(<"$f")" || continue
        [[ "$content" == *spotless* || "$content" == *google-java-format* ]] && return 0
    done
    return 1
}
