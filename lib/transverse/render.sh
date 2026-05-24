#!/usr/bin/env bash
# @module transverse/render
# @description Generic rendering primitives for human-facing terminal
# output. Pure-bash, dependency-free, multi-byte safe. Output goes to
# stdout by default; the caller redirects to stderr if needed (bash
# convention: logs/diagnostics on stderr, structured user output on
# stdout).
#
# Public API (P1):
#   render.repeat        - multi-byte-safe character repetition
#   render.section       - section heading
#   render.table         - read TSV from stdin, emit a Unicode
#                          box-drawing table sized from the data
#   render.color_enabled - auto-detect whether ANSI colors should be used
#
# Design notes
#   - No external dependencies (jq, glow, awk are not required).
#     Callers may transform their data with those tools before piping.
#   - Cells are plain text without ANSI escapes; widths are computed
#     from bash ${#cell} so multi-byte glyphs in cells (e.g. ✓) are
#     supported only when their byte count is interpreted correctly by
#     the runtime (bash 5+). Box-drawing border chars are constants and
#     not part of width math.

# Guard against double-sourcing.
[[ -n "${_BRIK_RENDER_LOADED:-}" ]] && return 0
_BRIK_RENDER_LOADED=1

# render.repeat <char> <n>
#   Print CHAR repeated N times. Safer than `printf '%*s' n ''` + `tr`
#   when CHAR is multi-byte UTF-8 (box-drawing chars do not survive
#   byte-oriented padding).
render.repeat() {
    local char="$1"
    local n="$2"
    local out=""
    local i
    for ((i=0; i<n; i++)); do
        out+="$char"
    done
    printf '%s' "$out"
}

# render.section <title>
#   Print a section heading on stdout. Style: "─ <title>" with a single
#   box-drawing horizontal as a visual marker. Used to delimit blocks of
#   structured user-facing output (Pipeline Report, Stages, Summary, ...)
#   distinct from the timestamped technical log stream.
render.section() {
    local title="$1"
    printf '─ %s\n' "$title"
}

# render.kv <key> <value> [--key-width N] [--width N] [--indent N] [--no-newline]
#   Print a "  key  value" line. Designed for KV lists (plan header,
#   stage metadata blocks, init info) and for fixed-width contexts
#   (single line padded to fit inside a box).
#
#   The key column is padded with spaces; that padding IS the separator
#   (no explicit ` : `). When --key-width is omitted, the minimum
#   separator between key and value is 2 spaces.
#
#   Options:
#     --key-width N    Pad the key column to N chars (default: length of
#                      key + 2, providing a minimum 2-space separator)
#     --width N        Right-pad the whole content to N chars; truncate if
#                      longer. Default 0 = no padding, content stays its
#                      natural length.
#     --indent N       Number of leading spaces (default: 2)
#     --no-newline     Do not emit the trailing newline (use for inline
#                      composition inside a box).
#
#   Defaults: "  key  value\n"
#   Aligned list (key column 15):
#     render.kv "Pipeline ID" "3542" --key-width 15
#     -> "  Pipeline ID    3542\n"
#   Fixed-width line for a 98-char inner box, no newline:
#     render.kv "runner" "image:tag" --key-width 8 --width 98 --no-newline
#     -> "  runner  image:tag<spaces to 98>"
render.kv() {
    local key="$1" value="$2"
    shift 2
    local key_width=0
    local total_width=0
    local indent=2
    local newline=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key-width)  key_width="$2"; shift 2 ;;
            --width)      total_width="$2"; shift 2 ;;
            --indent)     indent="$2"; shift 2 ;;
            --no-newline) newline=false; shift ;;
            *)            shift ;;
        esac
    done
    # Default: pad key + 2-space separator. If --key-width given but too
    # short to fit the key (or equal), enforce the 2-space minimum so the
    # value never sticks to the key.
    if (( key_width < ${#key} + 2 )); then
        key_width=$(( ${#key} + 2 ))
    fi

    local indent_str key_padded
    indent_str="$(render.repeat ' ' "$indent")"
    # Key padded as plain data (printf format string is fixed; key is the data arg).
    printf -v key_padded '%-*s' "$key_width" "$key"

    local content="${indent_str}${key_padded}${value}"

    if (( total_width > 0 )); then
        if (( ${#content} > total_width )); then
            content="${content:0:total_width}"
        else
            local pad
            pad="$(render.repeat ' ' $((total_width - ${#content})))"
            content="${content}${pad}"
        fi
    fi

    if $newline; then
        printf '%s\n' "$content"
    else
        printf '%s' "$content"
    fi
}

# render.color_enabled [<fd>]
#   Decide whether ANSI color escapes should be emitted on the given
#   file descriptor (default 1 = stdout). Returns 0 (true) if colors
#   should be used, 1 (false) otherwise.
#
#   Order of evaluation:
#     1. BRIK_RENDER_FORCE_COLOR=1  -> force on (tests, manual override)
#     2. BRIK_RENDER_NO_COLOR=1     -> force off
#     3. NO_COLOR set (no-color.org) -> force off
#     4. TERM=dumb                  -> force off (UNIX convention: a "dumb"
#                                       terminal has no ANSI support)
#     5. fd is a TTY                -> on
#     6. Known CI with ANSI rendering (GITLAB_CI, JENKINS_URL) -> on
#     7. Default                    -> off
render.color_enabled() {
    local fd="${1:-1}"
    [[ "${BRIK_RENDER_FORCE_COLOR:-}" == "1" ]] && return 0
    [[ "${BRIK_RENDER_NO_COLOR:-}" == "1" ]] && return 1
    [[ -n "${NO_COLOR:-}" ]] && return 1
    [[ "${TERM:-}" == "dumb" ]] && return 1
    [[ -t "$fd" ]] && return 0
    [[ "${GITLAB_CI:-}" == "true" ]] && return 0
    [[ -n "${JENKINS_URL:-}" ]] && return 0
    return 1
}

# render.color <name>
#   Emit the ANSI escape sequence for the named color (no newline),
#   or nothing if colors are disabled.
#
#   Names:
#     reset, bold, dim, red, green, yellow, blue, magenta, cyan, white
#
#   Decision (same env order as render.color_enabled but uses the
#   cached TTY status from source time; see _BRIK_RENDER_TTY below):
#     FORCE > NO_COLOR > CI markers > cached TTY decision
#
#   Designed to be safe inside `$(...)` command substitutions: the TTY
#   probe happens at source time (top-level shell), so subshells inherit
#   the right decision instead of probing their own pipe-fd.
render.color() {
    if [[ "${BRIK_RENDER_FORCE_COLOR:-}" != "1" ]]; then
        [[ "${BRIK_RENDER_NO_COLOR:-}" == "1" ]] && return 0
        [[ -n "${NO_COLOR:-}" ]] && return 0
        [[ "${TERM:-}" == "dumb" ]] && return 0
        if [[ "${GITLAB_CI:-}" != "true" && -z "${JENKINS_URL:-}" ]]; then
            [[ "${_BRIK_RENDER_TTY:-off}" == "off" ]] && return 0
        fi
    fi
    case "$1" in
        reset)   printf '\033[0m'  ;;
        bold)    printf '\033[1m'  ;;
        dim)     printf '\033[2m'  ;;
        red)     printf '\033[31m' ;;
        green)   printf '\033[32m' ;;
        yellow)  printf '\033[33m' ;;
        blue)    printf '\033[34m' ;;
        magenta) printf '\033[35m' ;;
        cyan)    printf '\033[36m' ;;
        white)   printf '\033[37m' ;;
        gray)    printf '\033[90m' ;;
        *)       return 1 ;;
    esac
}

# _render._level_meta <level>
#   Internal helper. Single source of truth for the level -> label + color
#   mapping. Used by render.status AND by logging.sh::_log._style_for so
#   both rendering surfaces share the same palette and label conventions.
#
#   Sets caller-visible variables:
#     _LEVEL_LABEL   the bracketed text  ("OK", "WARN", "DEBUG", ...)
#     _LEVEL_COLOR   the render.color name ("green", "yellow", "dim", "")
#                    empty string means "no color, render bracket only"
#
#   Recognized levels (with aliases):
#     debug                       -> DEBUG  dim
#     info                        -> INFO   (no color)
#     success                     -> OK     green
#     warn | warning              -> WARN   yellow
#     error                       -> ERROR  red
#     skip | skipped              -> SKIP   dim
#     <anything else>             -> <as-is uppercase? no: as-is> (no color)
#                                    (callers should not pass unknown levels)
_render._level_meta() {
    case "$1" in
        debug)         _LEVEL_LABEL="DEBUG"; _LEVEL_COLOR="dim"    ;;
        info)          _LEVEL_LABEL="INFO";  _LEVEL_COLOR="blue"   ;;
        success)       _LEVEL_LABEL="OK";    _LEVEL_COLOR="green"  ;;
        warn|warning)  _LEVEL_LABEL="WARN";  _LEVEL_COLOR="yellow" ;;
        error)         _LEVEL_LABEL="ERROR"; _LEVEL_COLOR="red"    ;;
        skip|skipped)  _LEVEL_LABEL="SKIP";  _LEVEL_COLOR="dim"    ;;
        *)             _LEVEL_LABEL="$1";    _LEVEL_COLOR=""       ;;
    esac
}

# render.icon <level>
#   Emit a visual emoji indicator for the given level. No trailing newline.
#   Suited for KV "Status" rows and table status columns where a glanceable
#   icon conveys the outcome more efficiently than a bracketed label.
#
#   Levels (with aliases):
#     success | ok                  -> ✅
#     error   | fail | failed       -> ❌
#     warn    | warning             -> ⚠️
#     skip    | skipped             -> ⏭️
#     info                          -> ℹ️
#     debug   | search              -> 🔍
#
#   Returns 1 for unknown levels (caller can fall back to render.status).
#   Width caveat: emojis are display-width 2 cells but bash counts them as
#   1 or 2 code points (the VS-16 selector adds +1 cp). Inside render.table
#   this can cause minor column-edge misalignment; we accept it because all
#   icons share the same display width and rows stay visually consistent.
render.icon() {
    case "$1" in
        success|ok)         printf '✅' ;;
        error|fail|failed)  printf '❌' ;;
        warn|warning)       printf '⚠️' ;;
        skip|skipped)       printf '⏭️' ;;
        info)               printf 'ℹ️' ;;
        debug|search)       printf '🔍' ;;
        *)                  return 1 ;;
    esac
}

# render.status <level> [<text>]
#   Print a colored "[LABEL]" status indicator, optionally followed by
#   a space and TEXT. The label color is fixed per level; TEXT is
#   uncolored (caller can wrap it manually with render.color if needed).
#
#   Levels and labels (delegated to _render._level_meta):
#     debug                -> [DEBUG]  (dim)
#     info                 -> [INFO]   (no color)
#     success              -> [OK]     (green)
#     warn | warning       -> [WARN]   (yellow)
#     error                -> [ERROR]  (red)
#     skip | skipped       -> [SKIP]   (dim)
#     <other>              -> [<other>] (no color)
#
#   No trailing newline. Caller adds one if needed.
render.status() {
    local level="$1"
    local text="${2:-}"
    local _LEVEL_LABEL _LEVEL_COLOR
    _render._level_meta "$level"
    if [[ -n "$_LEVEL_COLOR" ]]; then
        printf '[%s%s%s]' "$(render.color "$_LEVEL_COLOR")" "$_LEVEL_LABEL" "$(render.color reset)"
    else
        printf '[%s]' "$_LEVEL_LABEL"
    fi
    if [[ -n "$text" ]]; then
        printf ' %s' "$text"
    fi
}

# render.center <text> [--width N] [--no-newline]
#   Pad TEXT with leading + trailing spaces so its total length is N.
#   If TEXT is already >= N chars, no padding is applied (truncation
#   is left to the caller -- truncating centered text rarely makes
#   sense).
#
#   Options:
#     --width N        Target total width (default: ${#text}, i.e. no pad)
#     --no-newline     Do not emit the trailing newline
render.center() {
    local text="$1"
    shift
    local width=0
    local newline=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --width)      width="$2"; shift 2 ;;
            --no-newline) newline=false; shift ;;
            *)            shift ;;
        esac
    done

    local out="$text"
    if (( width > ${#text} )); then
        local pad_total=$(( width - ${#text} ))
        local pad_left=$(( pad_total / 2 ))
        local pad_right=$(( pad_total - pad_left ))
        local lsp rsp
        lsp="$(render.repeat ' ' "$pad_left")"
        rsp="$(render.repeat ' ' "$pad_right")"
        out="${lsp}${text}${rsp}"
    fi

    if $newline; then
        printf '%s\n' "$out"
    else
        printf '%s' "$out"
    fi
}

# render.blank [N]
#   Print a blank line N chars wide, terminated by a newline. Useful as
#   filler inside a render.box body when an empty visual line is needed.
#   Default N=0 emits a bare newline.
render.blank() {
    local n="${1:-0}"
    if (( n > 0 )); then
        render.repeat ' ' "$n"
    fi
    printf '\n'
}

# render.box [--inner-width N]
#   Read content lines from stdin, wrap each with "│ ... │" borders, and
#   emit top/bottom rules "┌──┐" / "└──┘". The caller is responsible for
#   the visual layout of each line (centering, KV padding, etc.) --
#   render.box only adds the box around what it receives.
#
#   Options:
#     --inner-width N   Force each line to exactly N chars (pads with
#                       spaces or truncates). Default 0 = derive from
#                       the length of the first input line.
#
#   Usage:
#     {
#         render.center "S T A G E" --width 98
#         render.blank 98
#         render.kv "runner" "image" --key-width 6 --width 98
#     } | render.box --inner-width 98
render.box() {
    local inner_width=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inner-width) inner_width="$2"; shift 2 ;;
            *)             shift ;;
        esac
    done

    local -a lines=()
    local line
    while IFS= read -r line; do
        lines+=("$line")
    done
    (( ${#lines[@]} == 0 )) && return 0

    (( inner_width == 0 )) && inner_width=${#lines[0]}

    local hr
    hr="$(render.repeat '─' "$inner_width")"

    printf '┌%s┐\n' "$hr"
    local l pad
    for l in "${lines[@]}"; do
        if (( ${#l} > inner_width )); then
            l="${l:0:inner_width}"
        elif (( ${#l} < inner_width )); then
            pad="$(render.repeat ' ' $((inner_width - ${#l})))"
            l="${l}${pad}"
        fi
        printf '│%s│\n' "$l"
    done
    printf '└%s┘\n' "$hr"
}

# render.table [--delim <char>]
#   Read delimiter-separated input from stdin (default delim TAB).
#   The first non-empty line is the header; subsequent non-empty lines
#   are body rows. Computes column widths from the data and emits a
#   Unicode box-drawing table to stdout.
#
#   Cells are plain text without ANSI escapes. Multi-byte content in
#   cells is preserved.
#
#   Usage:
#     { printf 'name\tage\n'; printf 'alice\t30\n'; } | render.table
#     { printf 'a|b\n1|2\n'; } | render.table --delim '|'
render.table() {
    local delim=$'\t'
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delim) delim="$2"; shift 2 ;;
            *)       shift ;;
        esac
    done

    local -a raw=()
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        raw+=("$line")
    done
    local n=${#raw[@]}
    (( n < 1 )) && return 0

    # Parse rows into a flat array (row-major) and compute column widths.
    local cols=0
    local -a flat=()
    local -a widths=()
    local r c
    for ((r=0; r<n; r++)); do
        local -a cells=()
        IFS="$delim" read -ra cells <<< "${raw[r]}"
        if (( r == 0 )); then
            cols=${#cells[@]}
            for ((c=0; c<cols; c++)); do widths[c]=0; done
        fi
        for ((c=0; c<cols; c++)); do
            local cell="${cells[c]:-}"
            flat[r * cols + c]="$cell"
            (( ${#cell} > widths[c] )) && widths[c]=${#cell}
        done
    done

    # Top rule
    printf '┌'
    for ((c=0; c<cols; c++)); do
        printf '%s' "$(render.repeat '─' $((widths[c] + 2)))"
        (( c < cols - 1 )) && printf '┬'
    done
    printf '┐\n'

    # Rows (header + mid rule + body)
    for ((r=0; r<n; r++)); do
        printf '│'
        for ((c=0; c<cols; c++)); do
            local cell="${flat[r * cols + c]}"
            local pad=$((widths[c] - ${#cell}))
            printf ' %s%s │' "$cell" "$(render.repeat ' ' "$pad")"
        done
        printf '\n'
        if (( r == 0 && n > 1 )); then
            printf '├'
            for ((c=0; c<cols; c++)); do
                printf '%s' "$(render.repeat '─' $((widths[c] + 2)))"
                (( c < cols - 1 )) && printf '┼'
            done
            printf '┤\n'
        fi
    done

    # Bottom rule
    printf '└'
    for ((c=0; c<cols; c++)); do
        printf '%s' "$(render.repeat '─' $((widths[c] + 2)))"
        (( c < cols - 1 )) && printf '┴'
    done
    printf '┘\n'
}

# ---------------------------------------------------------------------------
# Source-time TTY probe (used by render.color)
# ---------------------------------------------------------------------------
# `[[ -t 1 ]]` tests the *current* shell's fd 1. Inside a `$(...)` command
# substitution that fd is a pipe, so any TTY check performed from a
# subshell would incorrectly conclude "no TTY" even when the outer
# shell's stdout is a real terminal. We resolve TTY once here at source
# time -- this file is sourced from the top-level brik runtime shell
# where stdout still points at the user terminal -- and cache the
# result. Subsequent render.color calls from any subshell consult the
# cached value rather than re-probing.
if [[ -t 1 ]]; then
    _BRIK_RENDER_TTY="on"
else
    _BRIK_RENDER_TTY="off"
fi
