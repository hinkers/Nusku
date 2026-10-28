#!/usr/bin/env bash
# Logging and fail-loud command running. Sourced, not executed.

NUSKU_STEP="${NUSKU_STEP:-startup}"

log_init() {
    if [ -z "${NUSKU_LOG:-}" ]; then
        NUSKU_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nusku/install-$(date +%Y%m%d-%H%M%S).log"
    fi
    export NUSKU_LOG
    mkdir -p "$(dirname "$NUSKU_LOG")"
    touch "$NUSKU_LOG"
}

_log_ensure() {
    if [ -z "${NUSKU_LOG:-}" ] || [ ! -e "$NUSKU_LOG" ]; then
        log_init
    fi
}

# _log LEVEL COLOUR_CODE MSG: plain timestamped line to the log, colour on a TTY stderr.
_log() {
    local level="$1" colour="$2" msg="$3"
    _log_ensure
    printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "$level" "$msg" >>"$NUSKU_LOG"
    if [ -t 2 ]; then
        printf '\033[%sm[%s]\033[0m %s\n' "$colour" "$level" "$msg" >&2
    else
        printf '[%s] %s\n' "$level" "$msg" >&2
    fi
}

log_info() { _log INFO 34 "$*"; }
log_warn() { _log WARN 33 "$*"; }
log_error() { _log ERROR 31 "$*"; }

step() {
    NUSKU_STEP="$1"
    _log_ensure
    printf '%s ==> %s\n' "$(date +%H:%M:%S)" "$1" >>"$NUSKU_LOG"
    if [ -t 2 ]; then
        printf '\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$1" >&2
    else
        printf '==> %s\n' "$1" >&2
    fi
}

die() {
    _log_ensure
    printf '%s [FATAL] step: %s: %s\n' "$(date +%H:%M:%S)" "$NUSKU_STEP" "$*" >>"$NUSKU_LOG"
    {
        printf 'Nusku install failed during step: %s\n' "$NUSKU_STEP"
        printf '%s\n' "$*"
        printf 'Full log: %s\n' "$NUSKU_LOG"
    } >&2
    exit 1
}

# run_soft CMD ARGS...: like run (output to log and terminal) but returns the
# command's status and never dies. The command runs in a pipeline subshell.
# Exit status is carried via a temp file so neither pipefail nor errexit state
# of the caller matters or is altered.
run_soft() {
    _log_ensure
    local rcfile rc
    rcfile="$(mktemp)"
    printf '%s $ %s\n' "$(date +%H:%M:%S)" "$*" >>"$NUSKU_LOG"
    {
        local status=0
        "$@" || status=$?
        printf '%s' "$status" >"$rcfile"
    } 2>&1 | tee -a "$NUSKU_LOG" || true
    rc="$(cat "$rcfile" 2>/dev/null)"
    rm -f "$rcfile"
    return "${rc:-1}"
}

# run CMD ARGS...: run_soft, but failure calls die.
run() {
    run_soft "$@" || die "command failed: $*"
}
