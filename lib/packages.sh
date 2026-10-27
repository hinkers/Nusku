#!/usr/bin/env bash
# Package list reading and installers. Sourced, not executed.

# pkg_read_list FILE...: package names one per line; comments and blanks stripped; deduped, first-seen order.
pkg_read_list() {
    local f
    for f in "$@"; do
        [ -r "$f" ] || die "Package list not readable: $f"
        sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f"
    done | awk 'NF && !seen[$0]++'
}

# pkg_install_repo NAME...: install from the official repos.
pkg_install_repo() {
    [ "$#" -gt 0 ] || return 0
    run sudo pacman -S --needed --noconfirm "$@"
}

# pkg_install_aur NAME...: install from the AUR with the chosen helper.
pkg_install_aur() {
    [ "$#" -gt 0 ] || return 0
    local helper
    helper="$(answers_get AUR_HELPER)"
    [ -n "$helper" ] || die "AUR_HELPER is not set"
    run "$helper" -S --needed --noconfirm "$@"
}

# aur_bootstrap HELPER: build paru/yay from the AUR (-bin) unless already installed.
aur_bootstrap() {
    local helper="${1:-}"
    case "$helper" in
        paru | yay) ;;
        *) die "Unsupported AUR helper: '$helper' (expected paru or yay)" ;;
    esac
    if command -v "$helper" >/dev/null 2>&1; then
        log_info "AUR helper $helper already installed"
        return 0
    fi
    [ "$(id -u)" -ne 0 ] || die "aur_bootstrap must run as a normal user (makepkg refuses root)"
    # run dies on failure, so the clone, build and temp-dir cleanup share one subshell.
    run bash -c '
        set -e
        tmp="$(mktemp -d)"
        trap "rm -rf \"$tmp\"" EXIT
        git clone "https://aur.archlinux.org/$1-bin.git" "$tmp/$1"
        cd "$tmp/$1"
        makepkg -si --noconfirm
    ' _ "$helper"
}
