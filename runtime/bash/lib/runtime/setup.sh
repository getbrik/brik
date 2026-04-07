#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module setup
# @description Unified stack and prerequisite installation.
#
# Two categories, two strategies:
#
# PREREQUISITES (yq, jq, git, bash) - brik's own dependencies
#   - Virtualized (CI):  system package manager (apk/apt-get/yum/dnf)
#   - Non-virtualized (local): self-host yq/jq in BRIK_HOME/bin/, check-and-fail for git/bash
#
# STACKS (node, python, java, rust, dotnet) - project dependencies
#   - Virtualized (CI):  system package manager
#   - Non-virtualized (local): mise if available, otherwise check-and-fail
#
# Principle: on CI, own the container. On local, own only BRIK_HOME.

# Guard against double-sourcing
[[ -n "${_BRIK_SETUP_LOADED:-}" ]] && return 0
_BRIK_SETUP_LOADED=1

# Source logging if not already loaded
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# ---------------------------------------------------------------------------
# brik-runner image detection
# ---------------------------------------------------------------------------

# Check if running inside a brik-runner Docker image.
# Returns 0 (true) if the marker file exists, 1 (false) otherwise.
_setup._is_brik_runner() {
    [[ -f "/.brik-runner" ]]
}

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------

# Check if running in a virtualized (ephemeral CI) environment.
# Returns 0 (true) if virtualized, 1 (false) if local.
_setup._is_virtualized() {
    case "${BRIK_PLATFORM:-local}" in
        local) return 1 ;;
        *)     return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------

# Detect the best available system package manager (for CI containers).
# Prints: apk | apt-get | yum | dnf | "" (empty if none found).
# NOTE: keep in sync with _bootstrap_detect_pkg_manager() in
#       scripts/bootstrap-prereqs.sh
_setup._detect_system_pkg_manager() {
    local mgr
    for mgr in apt-get apk yum dnf; do
        if command -v "$mgr" >/dev/null 2>&1; then
            echo "$mgr"
            return 0
        fi
    done
    echo ""
    return 0
}

# ---------------------------------------------------------------------------
# Tool name mapping
# ---------------------------------------------------------------------------

# Map a logical stack/tool name to the binary to check on PATH.
_setup._tool_command() {
    local name="$1"
    case "$name" in
        node)   echo "node" ;;
        python) echo "python3" ;;
        java)   echo "java" ;;
        rust)   echo "cargo" ;;
        dotnet) echo "dotnet" ;;
        jq)     echo "jq" ;;
        yq)     echo "yq" ;;
        git)    echo "git" ;;
        bash)   echo "bash" ;;
        *)      echo "$name" ;;
    esac
}

# ---------------------------------------------------------------------------
# BRIK_HOME/bin management (local self-hosting)
# ---------------------------------------------------------------------------

# Ensure BRIK_HOME/bin exists and is on PATH (for current execution only).
_setup._ensure_brik_bin() {
    local brik_bin="${BRIK_HOME:-}/bin"
    if [[ -z "${BRIK_HOME:-}" ]]; then
        return 1
    fi
    mkdir -p "$brik_bin" 2>/dev/null || return 1
    case ":${PATH}:" in
        *":${brik_bin}:"*) ;;
        *) export PATH="${brik_bin}:${PATH}" ;;
    esac
    return 0
}

# Download a static binary to BRIK_HOME/bin/.
# Usage: _setup._self_host_binary <name> <url>
_setup._self_host_binary() {
    local name="$1"
    local url="$2"
    local target="${BRIK_HOME}/bin/${name}"

    _setup._ensure_brik_bin || {
        log.error "cannot create ${BRIK_HOME}/bin/ directory"
        return 5
    }

    log.info "downloading $name to ${target}"
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$target" "$url" && chmod +x "$target"
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL -o "$target" "$url" && chmod +x "$target"
    else
        log.error "cannot download $name: neither wget nor curl available"
        return 5
    fi

    if ! command -v "$name" >/dev/null 2>&1; then
        log.error "$name download succeeded but binary not found on PATH"
        return 5
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Per-manager install functions (system package managers - CI only)
# ---------------------------------------------------------------------------

_setup._install_via_apk() {
    local name="$1"
    local version="${2:-}"
    local packages

    case "$name" in
        node)   packages="nodejs npm" ;;
        python) packages="python3 py3-pip py3-setuptools" ;;
        java)   packages="${version:+openjdk${version}-jdk}"; packages="${packages:-openjdk21-jdk}"; packages="$packages maven" ;;
        rust)   packages="rust cargo" ;;
        dotnet) packages="${version:+dotnet${version%%.*}-sdk}"; packages="${packages:-dotnet8-sdk}" ;;
        jq)     packages="jq" ;;
        git)    packages="git" ;;
        bash)   packages="bash" ;;
        *)      packages="$name" ;;
    esac

    log.info "installing $name via apk ($packages)"
    # shellcheck disable=SC2086
    if ! apk add --no-cache $packages 2>&1; then
        log.error "apk install failed for $packages"
        return 5
    fi
    return 0
}

_setup._install_via_apt() {
    local name="$1"
    local version="${2:-}"
    local packages

    case "$name" in
        node)   packages="nodejs npm" ;;
        python) packages="python3 python3-pip python3-setuptools" ;;
        java)   packages="${version:+openjdk-${version}-jdk}"; packages="${packages:-openjdk-21-jdk}" ;;
        rust)   packages="rustc cargo" ;;
        dotnet) packages="${version:+dotnet-sdk-${version}.0}"; packages="${packages:-dotnet-sdk-8.0}" ;;
        jq)     packages="jq" ;;
        git)    packages="git" ;;
        bash)   packages="bash" ;;
        *)      packages="$name" ;;
    esac

    log.info "installing $name via apt-get ($packages)"
    if [[ -z "${_BRIK_APT_UPDATED:-}" ]]; then
        apt-get update -qq 2>&1 || true
        _BRIK_APT_UPDATED=1
    fi
    # shellcheck disable=SC2086
    if ! apt-get install -y -qq $packages 2>&1; then
        log.error "apt-get install failed for $packages"
        return 5
    fi
    return 0
}

_setup._install_via_yum() {
    local name="$1"
    local version="${2:-}"
    local packages

    case "$name" in
        node)   packages="nodejs npm" ;;
        python) packages="python3 python3-pip" ;;
        java)   packages="${version:+java-${version}-openjdk-devel}"; packages="${packages:-java-21-openjdk-devel}" ;;
        rust)   packages="rust cargo" ;;
        dotnet) packages="${version:+dotnet-sdk-${version}.0}"; packages="${packages:-dotnet-sdk-8.0}" ;;
        jq)     packages="jq" ;;
        git)    packages="git" ;;
        bash)   packages="bash" ;;
        *)      packages="$name" ;;
    esac

    log.info "installing $name via yum ($packages)"
    # shellcheck disable=SC2086
    if ! yum install -y $packages 2>&1; then
        log.error "yum install failed for $packages"
        return 5
    fi
    return 0
}

_setup._install_via_dnf() {
    local name="$1"
    local version="${2:-}"
    local packages

    case "$name" in
        node)   packages="nodejs npm" ;;
        python) packages="python3 python3-pip" ;;
        java)   packages="${version:+java-${version}-openjdk-devel}"; packages="${packages:-java-21-openjdk-devel}" ;;
        rust)   packages="rust cargo" ;;
        dotnet) packages="${version:+dotnet-sdk-${version}.0}"; packages="${packages:-dotnet-sdk-8.0}" ;;
        jq)     packages="jq" ;;
        git)    packages="git" ;;
        bash)   packages="bash" ;;
        *)      packages="$name" ;;
    esac

    log.info "installing $name via dnf ($packages)"
    # shellcheck disable=SC2086
    if ! dnf install -y $packages 2>&1; then
        log.error "dnf install failed for $packages"
        return 5
    fi
    return 0
}

# ---------------------------------------------------------------------------
# mise install (local stacks only)
# ---------------------------------------------------------------------------

_setup._install_via_mise() {
    local name="$1"
    local version="${2:-latest}"
    local mise_name

    case "$name" in
        node)   mise_name="node@${version}" ;;
        python) mise_name="python@${version}" ;;
        java)   mise_name="java@${version}" ;;
        rust)   mise_name="rust@${version}" ;;
        dotnet) mise_name="dotnet@${version}" ;;
        *)
            log.warn "mise: unknown tool '$name', trying as-is"
            mise_name="$name"
            ;;
    esac

    log.info "installing $name via mise ($mise_name)"
    if ! mise install "$mise_name" 2>&1; then
        log.error "mise install failed for $mise_name"
        return 5
    fi
    # Activate for current shell session only (not --global)
    eval "$(mise env --shell bash "$mise_name" 2>/dev/null)" || {
        log.warn "mise env failed for $mise_name, tool may not be on PATH"
    }
    return 0
}

# ---------------------------------------------------------------------------
# System package install dispatcher (CI only)
# ---------------------------------------------------------------------------

# Install a tool via a system package manager.
# Skips if the tool is already present on PATH.
# Usage: _setup._sys_pkg_install <manager> <logical_name> [version]
_setup._sys_pkg_install() {
    local mgr="$1"
    local name="$2"
    local version="${3:-}"

    local cmd
    cmd="$(_setup._tool_command "$name")"
    if command -v "$cmd" >/dev/null 2>&1; then
        log.debug "$name already installed ($(command -v "$cmd"))"
        return 0
    fi

    case "$mgr" in
        apk)     _setup._install_via_apk "$name" "$version" ;;
        apt-get) _setup._install_via_apt "$name" "$version" ;;
        yum)     _setup._install_via_yum "$name" "$version" ;;
        dnf)     _setup._install_via_dnf "$name" "$version" ;;
        *)
            log.error "unsupported package manager: $mgr"
            return 5
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Binary download helpers
# ---------------------------------------------------------------------------

# Build the yq download URL for the current platform.
_setup._yq_url() {
    local yq_version="${BRIK_YQ_VERSION:-v4.44.1}"
    local arch os
    arch="$(uname -m)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        arm64)   arch="arm64" ;;
    esac
    echo "https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_${os}_${arch}"
}

# Build the jq download URL for the current platform.
_setup._jq_url() {
    local jq_version="${BRIK_JQ_VERSION:-1.7.1}"
    local arch os
    arch="$(uname -m)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        arm64)   arch="arm64" ;;
    esac
    # jq naming: jq-linux-amd64, jq-macos-arm64
    [[ "$os" == "darwin" ]] && os="macos"
    echo "https://github.com/jqlang/jq/releases/download/jq-${jq_version}/jq-${os}-${arch}"
}

# ---------------------------------------------------------------------------
# Install yq
# ---------------------------------------------------------------------------

# Install yq with platform-appropriate strategy.
# CI: system package manager or binary download to /usr/local/bin/
# Local: self-host in BRIK_HOME/bin/
setup.install_yq() {
    if command -v yq >/dev/null 2>&1; then
        log.debug "yq already installed"
        return 0
    fi

    local url
    url="$(_setup._yq_url)"

    if _setup._is_virtualized; then
        local mgr
        mgr="$(_setup._detect_system_pkg_manager)"
        # apk/yum/dnf don't package yq -- always binary download on CI
        log.info "installing yq via binary download"
        local target="/usr/local/bin/yq"
        if command -v wget >/dev/null 2>&1; then
            wget -qO "$target" "$url" && chmod +x "$target"
        elif command -v curl >/dev/null 2>&1; then
            curl -sSL -o "$target" "$url" && chmod +x "$target"
        else
            log.error "cannot download yq: neither wget nor curl available"
            return 5
        fi
    else
        _setup._self_host_binary "yq" "$url"
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq installation failed"
        return 5
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

# Install core prerequisites: yq, jq, git, bash.
# Strategy depends on BRIK_PLATFORM (virtualized vs local).
setup.install_prerequisites() {
    if _setup._is_brik_runner; then
        log.info "brik-runner image detected, prerequisites already installed"
        return 0
    fi

    # Ensure BRIK_HOME/bin is on PATH for local self-hosted binaries
    if ! _setup._is_virtualized; then
        _setup._ensure_brik_bin || true
    fi

    # -- yq (always needs special handling: binary download) --
    setup.install_yq || {
        log.warn "yq installation failed, some features may not work"
    }

    if _setup._is_virtualized; then
        # CI: install jq/git/bash via system package manager
        local mgr
        mgr="$(_setup._detect_system_pkg_manager)"
        local tool
        for tool in jq git bash; do
            local cmd
            cmd="$(_setup._tool_command "$tool")"
            if command -v "$cmd" >/dev/null 2>&1; then
                log.debug "$tool already installed"
                continue
            fi
            if [[ -n "$mgr" ]]; then
                _setup._sys_pkg_install "$mgr" "$tool" || {
                    log.warn "$tool installation failed via $mgr"
                }
            else
                log.warn "$tool not found and no package manager available"
            fi
        done
    else
        # Local: self-host jq in BRIK_HOME/bin, check-and-fail for git/bash
        if ! command -v jq >/dev/null 2>&1; then
            local jq_url
            jq_url="$(_setup._jq_url)"
            _setup._self_host_binary "jq" "$jq_url" || {
                log.warn "jq installation failed, some features may not work"
            }
        fi
        local tool
        for tool in git bash; do
            if ! command -v "$tool" >/dev/null 2>&1; then
                log.error "$tool is required but not found on PATH"
                log.error "hint: install $tool via your system package manager"
                return 3
            fi
        done
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Stack installation
# ---------------------------------------------------------------------------

# Install a stack and its tools.
# CI: system package manager. Local: mise or check-and-fail.
# Reads version from BRIK_BUILD_<STACK>_VERSION environment variable.
setup.install_stack() {
    local stack="$1"

    if [[ -z "$stack" ]]; then
        log.error "stack name is required"
        return 2
    fi

    if _setup._is_brik_runner; then
        log.info "brik-runner image detected, stack tools already installed"
        return 0
    fi

    # Read version from env var (e.g., BRIK_BUILD_NODE_VERSION)
    local version_var="BRIK_BUILD_${stack^^}_VERSION"
    local version="${!version_var:-}"

    local cmd
    cmd="$(_setup._tool_command "$stack")"

    # Already available -- nothing to do
    if command -v "$cmd" >/dev/null 2>&1; then
        log.info "stack '$stack' already available ($cmd at $(command -v "$cmd"))"
        return 0
    fi

    if _setup._is_virtualized; then
        # CI: system package manager
        local mgr
        mgr="$(_setup._detect_system_pkg_manager)"
        if [[ -z "$mgr" ]]; then
            log.info "no system package manager detected, falling back to check mode"
            setup.check_stack "$stack"
            return $?
        fi
        _setup._sys_pkg_install "$mgr" "$stack" "$version" || {
            log.error "failed to install stack '$stack' via $mgr"
            return 5
        }
        # Post-install hooks (CI only - ephemeral environment)
        case "$stack" in
            python) _setup._python_post_install ;;
        esac
    else
        # Local: mise if available, otherwise check-and-fail
        if command -v mise >/dev/null 2>&1; then
            _setup._install_via_mise "$stack" "${version:-latest}" || {
                log.error "failed to install stack '$stack' via mise"
                return 5
            }
        else
            setup.check_stack "$stack"
            return $?
        fi
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Stack check (fallback)
# ---------------------------------------------------------------------------

# Verify that a stack's required tools are present on PATH.
# Returns BRIK_EXIT_MISSING_DEP (3) with a help message if not found.
setup.check_stack() {
    local stack="$1"
    local cmd
    cmd="$(_setup._tool_command "$stack")"

    if command -v "$cmd" >/dev/null 2>&1; then
        log.info "stack '$stack' verified ($cmd found at $(command -v "$cmd"))"
        return 0
    fi

    log.error "stack '$stack' is required but '$cmd' was not found on PATH"
    case "$stack" in
        node)
            log.error "hint: install Node.js via nvm, mise, or your system package manager"
            ;;
        python)
            log.error "hint: install Python via pyenv, mise, or your system package manager"
            ;;
        java)
            log.error "hint: install Java via sdkman, mise, or your system package manager"
            ;;
        rust)
            log.error "hint: install Rust via rustup (https://rustup.rs)"
            ;;
        dotnet)
            log.error "hint: install .NET via dotnet-install script or your system package manager"
            ;;
        *)
            log.error "hint: install '$stack' via your system package manager"
            ;;
    esac

    return 3
}

# ---------------------------------------------------------------------------
# Python post-install (CI only)
# ---------------------------------------------------------------------------

# Remove PEP 668 EXTERNALLY-MANAGED marker in CI containers (ephemeral)
# and install project dependencies if found.
# MUST NOT run on local -- modifying a developer's Python install is invasive.
_setup._python_post_install() {
    if ! _setup._is_virtualized; then
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    # Remove PEP 668 marker (safe only in ephemeral CI containers)
    local stdlib_path
    stdlib_path="$(python3 -c "import sysconfig; print(sysconfig.get_path('stdlib'))" 2>/dev/null)"
    if [[ -n "$stdlib_path" && -f "${stdlib_path}/EXTERNALLY-MANAGED" ]]; then
        log.info "removing PEP 668 EXTERNALLY-MANAGED marker"
        rm -f "${stdlib_path}/EXTERNALLY-MANAGED"
    fi

    # Install project dependencies if present
    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    if [[ -f "${project_dir}/pyproject.toml" ]] || [[ -f "${project_dir}/setup.py" ]]; then
        log.info "installing python project dependencies"
        if ! pip install --quiet . 2>&1; then
            log.warn "pip install failed for project dependencies"
        fi
    elif [[ -f "${project_dir}/requirements.txt" ]]; then
        log.info "installing python requirements"
        if ! pip install --quiet -r "${project_dir}/requirements.txt" 2>&1; then
            log.warn "pip install failed for requirements.txt"
        fi
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

# Prepare the runtime environment: install prerequisites and optionally a stack.
# This is the main entry point called by shared library wrappers.
# Usage: setup.prepare_env [stack]
setup.prepare_env() {
    local stack="${1:-}"

    log.info "preparing runtime environment"

    setup.install_prerequisites || {
        log.warn "prerequisite installation had issues"
    }

    if [[ -n "$stack" ]]; then
        local stack_rc=0
        setup.install_stack "$stack" || stack_rc=$?
        if [[ $stack_rc -ne 0 ]]; then
            log.error "stack installation failed for '$stack'"
            return "$stack_rc"
        fi
    fi

    log.info "runtime environment ready"
    return 0
}
