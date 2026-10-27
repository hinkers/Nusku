#!/usr/bin/env bash
# Timestamped backups of user files before they are overwritten. Sourced, not executed.
# Needs lib/log.sh.

# backup_dir: print this run's backup directory, creating it on first use.
backup_dir() {
    if [ -z "${NUSKU_RUN_ID:-}" ]; then
        NUSKU_RUN_ID="$(date +%Y%m%d-%H%M%S)"
        export NUSKU_RUN_ID
    fi
    local d="${XDG_STATE_HOME:-$HOME/.local/state}/nusku/backup-$NUSKU_RUN_ID"
    [ -d "$d" ] || mkdir -p "$d"
    printf '%s\n' "$d"
}

# backup_file PATH: copy PATH (if it exists) into the run's backup dir, keeping its layout.
backup_file() {
    local path="${1:?backup_file needs a path}" rel dest d
    [ -e "$path" ] || return 0
    # Fix the run id here: $(backup_dir) below runs in a subshell and could not export it.
    if [ -z "${NUSKU_RUN_ID:-}" ]; then
        NUSKU_RUN_ID="$(date +%Y%m%d-%H%M%S)"
        export NUSKU_RUN_ID
    fi
    d="$(backup_dir)"
    case "$path" in
        "$HOME"/*)
            rel="${path#"$HOME"/}"
            dest="$d/$rel"
            mkdir -p "$(dirname "$dest")"
            cp -a "$path" "$dest" || die "Could not back up $path"
            ;;
        *)
            rel="${path#/}"
            dest="$d/$rel"
            mkdir -p "$(dirname "$dest")"
            sudo cp -a "$path" "$dest" || die "Could not back up $path"
            sudo chown "$(id -u):$(id -g)" "$dest" || die "Could not chown backup of $path"
            ;;
    esac
    log_info "Backed up $path to $dest"
}
