#!/usr/bin/env bash
# Package list reading and installers. Sourced, not executed.

# pkg_read_list FILE...: package names one per line; comments and blanks stripped; deduped, first-seen order.
pkg_read_list() {
    local f
    # Validate first: die inside the pipeline below would only exit its subshell.
    for f in "$@"; do
        [ -r "$f" ] || die "Package list not readable: $f"
    done
    for f in "$@"; do
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

# _aur_build PKGBASE: clone PKGBASE from the AUR and makepkg -si it.
_aur_build() {
    # run dies on failure, so the clone, build and temp-dir cleanup share one subshell.
    run bash -c '
        set -e
        tmp="$(mktemp -d)"
        trap "rm -rf \"$tmp\"" EXIT
        git clone "https://aur.archlinux.org/$1.git" "$tmp/$1"
        cd "$tmp/$1"
        makepkg -si --noconfirm
    ' _ "$1"
}

# _aur_helper_works HELPER: the helper is on PATH and actually runs. A prebuilt -bin
# helper breaks when pacman bumps the libalpm soname before the AUR package is rebuilt.
_aur_helper_works() {
    command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1
}

# _aur_drop_bin HELPER: remove a broken prebuilt HELPER-bin so the source build can replace it.
_aur_drop_bin() {
    local p
    for p in "$1-bin" "$1-bin-debug"; do
        if pacman -Qq "$p" >/dev/null 2>&1; then
            run sudo pacman -Rdd --noconfirm "$p"
        fi
    done
}

# aur_bootstrap HELPER: install paru/yay from the AUR unless a working one is present.
# Tries the prebuilt -bin package first; falls back to building from source if it won't run.
aur_bootstrap() {
    local helper="${1:-}"
    case "$helper" in
        paru | yay) ;;
        *) die "Unsupported AUR helper: '$helper' (expected paru or yay)" ;;
    esac
    if _aur_helper_works "$helper"; then
        log_info "AUR helper $helper already installed"
        return 0
    fi
    [ "$(id -u)" -ne 0 ] || die "aur_bootstrap must run as a normal user (makepkg refuses root)"
    if ! command -v "$helper" >/dev/null 2>&1; then
        _aur_build "$helper-bin"
        _aur_helper_works "$helper" && return 0
    fi
    log_warn "$helper is installed but does not run (likely built against an older pacman); building it from source"
    _aur_drop_bin "$helper"
    _aur_build "$helper"
    _aur_helper_works "$helper" || die "AUR helper $helper still does not run after building it from source"
}

# pkg_install_repo_swap_rust NAME...: pkg_install_repo, except that rustup first replaces an
# installed rust package (they conflict; --ask=4 answers the removal prompt).
pkg_install_repo_swap_rust() {
    local n swap=0
    local -a rest=()
    for n in "$@"; do
        if [ "$n" = rustup ] && pacman -Qq rust >/dev/null 2>&1; then
            swap=1
        else
            rest+=("$n")
        fi
    done
    if [ "$swap" -eq 1 ]; then
        log_warn "Replacing the rust package with rustup (needed for the Rust language option)"
        run sudo pacman -S --needed --noconfirm --ask=4 rustup
    fi
    pkg_install_repo "${rest[@]}"
}

# pkg_enable_multilib: enable [multilib] in pacman.conf (NUSKU_ETC overrides /etc, for tests)
# and refresh with a full upgrade; no-op when it is already enabled.
pkg_enable_multilib() {
    local conf="${NUSKU_ETC:-/etc}/pacman.conf" tmp
    if grep -q '^\[multilib\]' "$conf"; then
        return 0
    fi
    backup_file "$conf"
    tmp="$(mktemp)"
    if grep -q '^#\[multilib\]$' "$conf"; then
        sed -e 's/^#\[multilib\]$/[multilib]/' -e '/^\[multilib\]$/{n;s/^#Include/Include/}' "$conf" >"$tmp"
    else
        {
            cat "$conf"
            printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n'
        } >"$tmp"
    fi
    run sudo install -m 644 "$tmp" "$conf"
    rm -f "$tmp"
    run sudo pacman -Syu --noconfirm
}

# pkg_flathub_remote: add the Flathub remote system-wide (soft: Flatpak apps just fail without it).
pkg_flathub_remote() {
    run_soft sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# pkg_install_flatpak ID: install a Flatpak app from Flathub (soft).
pkg_install_flatpak() {
    run_soft sudo flatpak install --system -y --noninteractive flathub "$1"
}
