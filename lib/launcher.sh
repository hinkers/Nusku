# Nusku - launcher tweaks: hide clutter and swap icons via ~/.local/share/applications.
# Needs lib/log.sh (log_info).
#
# Each tweak is a copy of the app's own .desktop file with one change and an X-Nusku-Override
# marker. A file without the marker is the user's own and is never touched. Managed copies whose
# app or list entry is gone are removed.

NUSKU_LAUNCHER_MARK="X-Nusku-Override=true"

# _launcher_source FILE: the installed system copy of FILE (first match), or nothing.
_launcher_source() {
    local d
    local IFS=:
    for d in ${NUSKU_LAUNCHER_DIRS:-${XDG_DATA_DIRS:-/usr/local/share:/usr/share}}; do
        if [ -f "$d/applications/$1" ]; then
            printf '%s\n' "$d/applications/$1"
            return 0
        fi
    done
    return 1
}

# _launcher_edit KEY VALUE < desktop: set KEY=VALUE in [Desktop Entry] (replacing any existing
# line there), add the marker, leave other sections (actions) alone.
_launcher_edit() {
    awk -v key="$1" -v val="$2" -v mark="$NUSKU_LAUNCHER_MARK" '
        function finish() { if (inmain) { if (!done) print key "=" val; print mark; inmain = 0 } }
        /^\[/ { finish(); inmain = ($0 == "[Desktop Entry]"); done = 0; print; next }
        inmain && index($0, key "=") == 1 { print key "=" val; done = 1; next }
        inmain && $0 == mark { next }
        { print }
        END { finish() }'
}

# launcher_apply LIST: apply every hide/icon line of LIST to ${XDG_DATA_HOME}/applications.
launcher_apply() {
    local list="$1" dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local verb file icon src dest keep=" " n=0
    mkdir -p "$dir"
    while read -r verb file icon; do
        case "$verb" in hide | icon) ;; *) continue ;; esac
        dest="$dir/$file"
        if [ -e "$dest" ] && ! grep -qxF "$NUSKU_LAUNCHER_MARK" "$dest"; then
            continue # the user's own entry
        fi
        src="$(_launcher_source "$file")" || continue
        keep+="$file "
        if [ "$verb" = hide ]; then
            _launcher_edit NoDisplay true <"$src" >"$dest.tmp"
        else
            _launcher_edit Icon "$icon" <"$src" >"$dest.tmp"
        fi
        mv -f "$dest.tmp" "$dest"
        n=$((n + 1))
    done < <(sed 's/#.*$//' "$list")

    # Managed copies no longer wanted (entry removed from the list, or app uninstalled).
    local f
    for f in "$dir"/*.desktop; do
        [ -f "$f" ] || continue
        grep -qxF "$NUSKU_LAUNCHER_MARK" "$f" || continue
        case "$keep" in *" ${f##*/} "*) ;; *) rm -f "$f" ;; esac
    done
    log_info "Launcher: $n entries tweaked"
}
