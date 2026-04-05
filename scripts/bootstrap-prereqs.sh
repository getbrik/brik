#!/usr/bin/env sh
# @description Standalone bootstrap script for CI prerequisites.
#
# Installs yq, jq, git, and bash BEFORE BRIK_HOME is available.
# This script has NO dependency on the Brik runtime -- it uses echo instead
# of log.info and contains a minimal copy of the package manager detection.
#
# Usage (from pipeline.yml before_script):
#   . /path/to/bootstrap-prereqs.sh
#   bootstrap_prereqs
#
# Note: uses /bin/sh for maximum portability (Alpine default shell).

# Detect the best available package manager.
# Prints: apk | apt-get | yum | dnf | "" (empty if none)
# NOTE: keep in sync with _setup._detect_system_pkg_manager() in
#       runtime/bash/lib/runtime/setup.sh
_bootstrap_detect_pkg_manager() {
    for _mgr in apk apt-get yum dnf; do
        if command -v "$_mgr" >/dev/null 2>&1; then
            echo "$_mgr"
            return 0
        fi
    done
    echo ""
    return 0
}

# Install yq via binary download (no package manager needed).
_bootstrap_install_yq() {
    if command -v yq >/dev/null 2>&1; then
        return 0
    fi

    echo "[brik] Installing yq..."
    _yq_version="${BRIK_YQ_VERSION:-v4.44.1}"
    _arch="$(uname -m)"
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "$_arch" in
        x86_64)  _arch="amd64" ;;
        aarch64|arm64) _arch="arm64" ;;
    esac

    _url="https://github.com/mikefarah/yq/releases/download/${_yq_version}/yq_${_os}_${_arch}"

    if command -v wget >/dev/null 2>&1; then
        wget -qO /usr/local/bin/yq "$_url" && chmod +x /usr/local/bin/yq
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL -o /usr/local/bin/yq "$_url" && chmod +x /usr/local/bin/yq
    else
        echo "[brik] WARNING: cannot download yq (no wget or curl)" >&2
        return 1
    fi
}

# Install a tool via the detected package manager.
# Usage: _bootstrap_install_tool <manager> <tool_name>
_bootstrap_install_tool() {
    _mgr="$1"
    _tool="$2"

    if command -v "$_tool" >/dev/null 2>&1; then
        return 0
    fi

    echo "[brik] Installing ${_tool}..."
    case "$_mgr" in
        apk)     apk add --no-cache "$_tool" ;;
        apt-get)
            if [ -z "${_BOOTSTRAP_APT_UPDATED:-}" ]; then
                apt-get update -qq 2>/dev/null || true
                _BOOTSTRAP_APT_UPDATED=1
            fi
            apt-get install -y -qq "$_tool"
            ;;
        yum) yum install -y "$_tool" ;;
        dnf) dnf install -y "$_tool" ;;
        *)
            echo "[brik] WARNING: no package manager available to install ${_tool}" >&2
            return 1
            ;;
    esac
}

# Main entry point: install all CI prerequisites.
bootstrap_prereqs() {
    _mgr="$(_bootstrap_detect_pkg_manager)"

    _bootstrap_install_yq
    _bootstrap_install_tool "$_mgr" "jq"
    _bootstrap_install_tool "$_mgr" "git"
    _bootstrap_install_tool "$_mgr" "bash"

    return 0
}
