#!/usr/bin/env bash
# Checks run before install.sh touches anything. Sourced, not executed.
# Test hooks: NUSKU_ARCH_RELEASE (default /etc/arch-release), NUSKU_EUID (default $EUID).

preflight_checks() {
    step "Preflight checks"

    [ -e "${NUSKU_ARCH_RELEASE:-/etc/arch-release}" ] ||
        die "Nusku only supports Arch Linux, and this does not look like Arch. Install it on a fresh Arch base install."

    [ "${NUSKU_EUID:-$EUID}" -ne 0 ] ||
        die "Run install.sh as your normal user, not root (it uses sudo when needed)."

    sudo -v ||
        die "Nusku needs sudo access. Make sure your user can use sudo (is in the wheel group) and you typed the password correctly."

    curl -fsS --max-time 10 https://archlinux.org >/dev/null ||
        die "There is no network connection (could not reach archlinux.org). Connect to the internet and run install.sh again."

    log_info "Preflight checks passed"
}

# Installs the tools the installer itself needs (pciutils: lspci for gpu_suggest); the -Syu also does a full system upgrade.
preflight_bootstrap() {
    step "Installing bootstrap packages"
    run sudo pacman -Syu --needed --noconfirm gum jq git base-devel curl pciutils
}
