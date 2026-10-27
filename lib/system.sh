#!/usr/bin/env bash
# SDDM theme and config, services, login shell, user dirs, GTK settings. Sourced, not executed.
# Needs lib/log.sh, lib/answers.sh, lib/backup.sh, lib/gpu.sh.

NUSKU_ROOT="${NUSKU_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SDDM_THEME_VERSION="v1.1.2"
SDDM_THEME_URL_BASE="https://github.com/catppuccin/sddm/releases/download"
# Session file basename (without .desktop) in /usr/share/wayland-sessions, from the hyprland package.
NUSKU_SESSION="hyprland"
NUSKU_SDDM_BG_DIR="/var/lib/nusku/sddm-background"

# _sys_install_file SRC DEST: sudo-install SRC at DEST (mode 644), skipping identical content
# and backing up a differing existing file first.
_sys_install_file() {
    local src="$1" dest="$2"
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        return 0
    fi
    backup_file "$dest"
    run sudo install -D -m 644 "$src" "$dest"
}

# sddm_prepare_background_dir: directory the wallpaper tool drops the greeter background into.
sddm_prepare_background_dir() {
    local owner
    owner="$(id -u):$(id -g)"
    run sudo mkdir -p "$NUSKU_SDDM_BG_DIR"
    run sudo chown "$owner" "$NUSKU_SDDM_BG_DIR"
    run sudo chmod 755 "$NUSKU_SDDM_BG_DIR"
}

# sddm_install_theme ACCENT: download the pinned catppuccin/sddm release and install it.
sddm_install_theme() {
    local accent="${1:?accent needed}" name themes dir tmp url main
    name="catppuccin-mocha-$accent"
    themes="${NUSKU_SDDM_THEMES:-/usr/share/sddm/themes}"
    dir="$themes/$name"
    if [ "$(cat "$dir/.nusku-version" 2>/dev/null || true)" = "$SDDM_THEME_VERSION" ]; then
        log_info "SDDM theme $name $SDDM_THEME_VERSION already installed"
    else
        tmp="$(mktemp -d)"
        url="$SDDM_THEME_URL_BASE/$SDDM_THEME_VERSION/$name-sddm.zip"
        if ! (run curl -fsSL -o "$tmp/theme.zip" "$url"); then
            rm -rf "$tmp"
            exit 1
        fi
        if ! (run bsdtar -xf "$tmp/theme.zip" -C "$tmp"); then
            rm -rf "$tmp"
            exit 1
        fi
        [ -f "$tmp/$name/Main.qml" ] || {
            rm -rf "$tmp"
            die "SDDM theme archive has no $name/Main.qml"
        }
        main="$tmp/$name/Main.qml"
        if ! grep -q 'fillMode: Image.PreserveAspectCrop' "$main"; then
            log_warn "SDDM theme Main.qml lacks PreserveAspectCrop; patching"
            if grep -q 'fillMode:' "$main"; then
                sed -i 's/fillMode:.*/fillMode: Image.PreserveAspectCrop/' "$main"
            else
                sed -i '/id: backgroundImage/a\    fillMode: Image.PreserveAspectCrop' "$main"
            fi
        fi
        printf '%s\n' "$SDDM_THEME_VERSION" >"$tmp/$name/.nusku-version"
        run sudo mkdir -p "$themes"
        run sudo rm -rf "$dir"
        run sudo cp -r "$tmp/$name" "$dir"
        rm -rf "$tmp"
    fi
    _sys_install_file "$NUSKU_ROOT/sddm/theme.conf.user.tmpl" "$dir/theme.conf.user"
}

# sddm_write_config ACCENT GPU TEST_AUTOLOGIN: /etc/sddm.conf.d drop-ins.
sddm_write_config() {
    local accent="${1:?accent needed}" gpu="${2:-}" autologin="${3:-}"
    local confd tmp user
    confd="${NUSKU_ETC:-/etc}/sddm.conf.d"
    user="${USER:-$(id -un)}"
    tmp="$(mktemp)"
    sed "s/@ACCENT@/$accent/g" "$NUSKU_ROOT/sddm/10-nusku.conf" >"$tmp"
    _sys_install_file "$tmp" "$confd/10-nusku.conf"
    if [ "$gpu" = "vm" ] && [ "$autologin" = "1" ]; then
        sed -e "s/@USER@/$user/g" -e "s/@SESSION@/$NUSKU_SESSION/g" \
            "$NUSKU_ROOT/sddm/20-autologin.conf.tmpl" >"$tmp"
        _sys_install_file "$tmp" "$confd/20-autologin.conf"
    elif [ -e "$confd/20-autologin.conf" ]; then
        backup_file "$confd/20-autologin.conf"
        run sudo rm -f "$confd/20-autologin.conf"
    fi
    rm -f "$tmp"
}

# services_enable: enable (never start) system and user units.
services_enable() {
    local units=(sddm NetworkManager bluetooth power-profiles-daemon) vm=() u
    if [ "$(answers_get GPU)" = "vm" ]; then
        read -ra vm <<<"$(gpu_vm_services "$(gpu_virt)")"
        units+=("${vm[@]}")
    fi
    run sudo systemctl enable "${units[@]}"
    # User units may be socket-activated or preset-enabled: a failure here is not fatal.
    for u in pipewire pipewire-pulse wireplumber; do
        (run sudo systemctl --global enable "$u") ||
            log_warn "Could not enable user unit $u (already handled by presets?)"
    done
}

# shell_set_zsh: make zsh the login shell unless it already is.
shell_set_zsh() {
    local user="${USER:-$(id -un)}" cur
    cur="$(getent passwd "$user" | cut -d: -f7)"
    case "$cur" in
        */zsh)
            log_info "Login shell is already zsh"
            return 0
            ;;
    esac
    run sudo chsh -s /usr/bin/zsh "$user"
}

# user_dirs_setup: XDG user dirs and the screenshots folder.
user_dirs_setup() {
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        run xdg-user-dirs-update
    else
        log_warn "xdg-user-dirs-update not found; skipping"
    fi
    mkdir -p "$HOME/Pictures/Screenshots"
}

# gtk_apply_settings: best-effort gsettings (needs a session bus; settings.ini covers the rest).
gtk_apply_settings() {
    local accent="${1:-blue}"
    if ! command -v gsettings >/dev/null 2>&1 ||
        ! gsettings get org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
        log_warn "No gsettings or session bus; skipping gsettings (settings.ini still applies)"
        return 0
    fi
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || log_warn "gsettings gtk-theme failed"
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' || log_warn "gsettings icon-theme failed"
    gsettings set org.gnome.desktop.interface cursor-theme "catppuccin-mocha-$accent-cursors" || log_warn "gsettings cursor-theme failed"
    gsettings set org.gnome.desktop.interface font-name 'Noto Sans 11' || log_warn "gsettings font-name failed"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || log_warn "gsettings color-scheme failed"
}

# system_configure: everything above, driven by the answers.
system_configure() {
    local accent gpu autologin
    accent="$(answers_get ACCENT)"
    gpu="$(answers_get GPU)"
    autologin="$(answers_get TEST_AUTOLOGIN)"
    [ -n "$accent" ] || accent="blue"
    step "SDDM"
    sddm_prepare_background_dir
    sddm_install_theme "$accent"
    sddm_write_config "$accent" "$gpu" "$autologin"
    step "Services"
    services_enable
    step "Login shell and user directories"
    shell_set_zsh
    user_dirs_setup
    gtk_apply_settings "$accent"
}
