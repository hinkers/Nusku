#!/usr/bin/env bash
# ArtCraft apps (github.com/storytold): each release's official Arch package, installed with
# pacman -U; the ArtCraft Launcher then keeps them updated. Sourced, not executed.
# Needs lib/log.sh (log_info, run_soft) and lib/apps.sh (apps_label, NUSKU_APP_FAILURES/NOTES).

: "${NUSKU_ARTCRAFT_BASE:=https://github.com/storytold}"

# Set to 1 by artcraft_install_soft when it installed the launcher in this run.
export NUSKU_ARTCRAFT_LAUNCHER_NEW=0

# artcraft_stem REPO: the package stem (the launcher's repo is named differently).
artcraft_stem() {
    if [ "$1" = craft-launcher ]; then
        printf 'artcraft-launcher\n'
    else
        printf '%s\n' "$1"
    fi
}

# artcraft_installed STEM: status 0 when the release package ai.storyteller.<stem> is installed.
artcraft_installed() {
    pacman -Q "ai.storyteller.$1" >/dev/null 2>&1
}

# artcraft_foreign STEM: print an installed <stem>, <stem>-bin or <stem>-git package (the AUR
# copies) and return 0; return 1 when there is none.
artcraft_foreign() {
    local n
    for n in "$1" "$1-bin" "$1-git"; do
        if pacman -Qq "$n" >/dev/null 2>&1; then
            printf '%s\n' "$n"
            return 0
        fi
    done
    return 1
}

# artcraft_fetch REPO DIR: download the latest release's x86_64 Arch package into DIR, verify it
# against SHA256SUMS.txt and print its path. On failure: a one-line reason on stderr, status 1.
artcraft_fetch() {
    local repo="$1" dir="$2" url sums line sum file
    url="$NUSKU_ARTCRAFT_BASE/$repo/releases/latest/download"
    sums="$dir/SHA256SUMS.txt"
    curl -fsSL --retry 2 -o "$sums" "$url/SHA256SUMS.txt" 2>>"${NUSKU_LOG:-/dev/null}" || {
        echo "download failed" >&2
        return 1
    }
    line="$(awk '{ f = $2; sub(/^\*/, "", f) } f ~ /-linux-x86_64\.pkg\.tar\.zst$/ { print $1, f; exit }' "$sums")"
    if [ -z "$line" ] || [[ "${line#* }" == */* ]]; then
        echo "no x86_64 Arch package in the latest release" >&2
        return 1
    fi
    sum="${line% *}"
    file="${line#* }"
    curl -fsSL --retry 2 -o "$dir/$file" "$url/$file" 2>>"${NUSKU_LOG:-/dev/null}" || {
        echo "download failed" >&2
        return 1
    }
    if ! (cd "$dir" && printf '%s  %s\n' "$sum" "$file" | sha256sum -c --status); then
        echo "checksum mismatch" >&2
        return 1
    fi
    printf '%s/%s\n' "$dir" "$file"
}

# _artcraft_one REPO LABEL: install one release package; failures go to NUSKU_APP_FAILURES.
# Status 0 when the app is present afterwards (installed now, already there, or an AUR copy).
_artcraft_one() {
    local repo="$1" label="$2" stem foreign tmp pkg reason
    stem="$(artcraft_stem "$repo")"
    if artcraft_installed "$stem"; then
        log_info "$label is already installed"
        return 0
    fi
    if foreign="$(artcraft_foreign "$stem")"; then
        NUSKU_APP_NOTES+=("$label is installed from the AUR ($foreign); the ArtCraft Launcher won't update it.")
        return 0
    fi
    log_info "Downloading $label from $NUSKU_ARTCRAFT_BASE/$repo/releases/latest/download"
    tmp="$(mktemp -d)"
    if pkg="$(artcraft_fetch "$repo" "$tmp" 2>"$tmp/err")"; then
        if run_soft sudo pacman -U --noconfirm --needed "$pkg"; then
            rm -rf "$tmp"
            return 0
        fi
        reason="install failed"
    else
        reason="$(head -n1 "$tmp/err")"
    fi
    rm -rf "$tmp"
    NUSKU_APP_FAILURES+=("$label: ${reason:-download failed}")
    return 1
}

# artcraft_autostart_entry FILE: write the launcher's own autostart entry unless FILE exists.
artcraft_autostart_entry() {
    [ -e "$1" ] && return 0
    mkdir -p "$(dirname "$1")"
    cat >"$1" <<'ENTRY'
[Desktop Entry]
Type=Application
Name=ArtCraft Launcher
Comment=Install and update the Craft App Suite
Exec=/usr/bin/artcraft-launcher --hidden
Icon=ai.storyteller.artcraft-launcher
Terminal=false
X-GNOME-Autostart-enabled=true
ENTRY
}

# artcraft_install_soft BATCHES: for each "artcraft APP_ID REPO" line (the launcher line comes
# first), install the release package. A failure is recorded and the run goes on.
artcraft_install_soft() {
    local kind id repo label
    while read -r kind id repo; do
        [ "$kind" = artcraft ] || continue
        if [ "$id" = launcher ]; then
            label="ArtCraft Launcher"
            # Fresh means this run installs it (not installed before, no AUR copy).
            if ! artcraft_installed "$(artcraft_stem "$repo")" && ! artcraft_foreign "$(artcraft_stem "$repo")" >/dev/null; then
                if _artcraft_one "$repo" "$label"; then
                    NUSKU_ARTCRAFT_LAUNCHER_NEW=1
                    artcraft_autostart_entry "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/ai.storyteller.artcraft-launcher.desktop"
                else
                    NUSKU_APP_NOTES+=("The ArtCraft Launcher was not installed, so ArtCraft apps won't update until it is.")
                fi
            else
                _artcraft_one "$repo" "$label" || true
            fi
            continue
        fi
        _artcraft_one "$repo" "$(apps_label "$id")" || true
    done <<<"$1"
}
