bats_require_minimum_version 1.5.0

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP NUSKU_RUN_ID
    export NUSKU_ETC="$BATS_TEST_TMPDIR/etc" NUSKU_SDDM_THEMES="$BATS_TEST_TMPDIR/themes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS" "$NUSKU_ETC"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    export CALLS
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\nexec "$@"\n' >"$STUBS/sudo"
    # curl stub: builds a theme zip-like marker; bsdtar stub creates the theme dir named in the url.
    printf '#!/bin/sh\necho "curl $*" >>"$CALLS"\nfor a; do u="$a"; done\nout=""\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\nbasename "$u" >"$out"\n' >"$STUBS/curl"
    cat >"$STUBS/bsdtar" <<'EOS'
#!/bin/sh
echo "bsdtar $*" >>"$CALLS"
zip="$2"; dest="$4"
n="$(cat "$zip")"; n="${n%-sddm.zip}"
mkdir -p "$dest/$n"
printf 'Image {\n id: backgroundImage\n}\n' >"$dest/$n/Main.qml"
printf '[General]\n' >"$dest/$n/theme.conf"
EOS
    printf '#!/bin/sh\necho "systemctl $*" >>"$CALLS"\n' >"$STUBS/systemctl"
    printf '#!/bin/sh\necho "chsh $*" >>"$CALLS"\n' >"$STUBS/chsh"
    printf '#!/bin/sh\necho kvm\n' >"$STUBS/systemd-detect-virt"
    chmod +x "$STUBS"/*
    HASH_OK="$(printf 'catppuccin-mocha-teal-sddm.zip
' | sha256sum | cut -d" " -f1)"
    export HASH_OK
}

in_sub() {
    PATH="$STUBS:$PATH" bash -c 'source lib/log.sh; source lib/answers.sh; source lib/backup.sh; source lib/gpu.sh; source lib/system.sh; SDDM_THEME_SHA256[teal]="${HASH_TEAL:-$HASH_OK}"; '"$1"
}

@test "writes theme conf with accent" {
    run in_sub "sddm_write_config mauve amd 0"
    [ "$status" -eq 0 ]
    grep -qx 'Current=catppuccin-mocha-mauve' "$NUSKU_ETC/sddm.conf.d/10-nusku.conf"
    [ ! -e "$NUSKU_ETC/sddm.conf.d/20-autologin.conf" ]
}

@test "existing differing config is backed up, identical is skipped" {
    mkdir -p "$NUSKU_ETC/sddm.conf.d"
    echo old >"$NUSKU_ETC/sddm.conf.d/10-nusku.conf"
    run in_sub "sddm_write_config blue amd 0"
    [ "$status" -eq 0 ]
    [ -n "$(find "$XDG_STATE_HOME" -path '*backup-*' -name 10-nusku.conf)" ]
    : >"$CALLS"
    run in_sub "sddm_write_config blue amd 0"
    run grep -c 'install' "$CALLS"
    [ "$output" = "0" ]
}

@test "autologin written only for vm + TEST_AUTOLOGIN=1" {
    run in_sub "sddm_write_config blue vm 1"
    [ "$status" -eq 0 ]
    f="$NUSKU_ETC/sddm.conf.d/20-autologin.conf"
    grep -q '^User=' "$f"
    grep -qx 'Session=hyprland' "$f"
}

@test "autologin removed when GPU is not vm" {
    mkdir -p "$NUSKU_ETC/sddm.conf.d"
    echo x >"$NUSKU_ETC/sddm.conf.d/20-autologin.conf"
    run in_sub "sddm_write_config blue amd 1"
    [ "$status" -eq 0 ]
    [ ! -e "$NUSKU_ETC/sddm.conf.d/20-autologin.conf" ]
}

@test "autologin removed when vm but TEST_AUTOLOGIN is not 1" {
    mkdir -p "$NUSKU_ETC/sddm.conf.d"
    echo x >"$NUSKU_ETC/sddm.conf.d/20-autologin.conf"
    run in_sub "sddm_write_config blue vm 0"
    [ ! -e "$NUSKU_ETC/sddm.conf.d/20-autologin.conf" ]
}

@test "sddm_install_theme downloads, patches fillMode, writes theme.conf.user, marks version" {
    run in_sub "sddm_install_theme teal"
    [ "$status" -eq 0 ]
    d="$NUSKU_SDDM_THEMES/catppuccin-mocha-teal"
    grep -q 'catppuccin-mocha-teal-sddm.zip' "$CALLS"
    grep -q 'fillMode: Image.PreserveAspectCrop' "$d/Main.qml"
    grep -q 'CustomBackground="true"' "$d/theme.conf.user"
    grep -q '/var/lib/nusku/sddm-background/background' "$d/theme.conf.user"
    grep -q 'JetBrains' "$d/theme.conf.user"
    [ "$(cat "$d/.nusku-version")" = "v1.1.2" ]
}

@test "sddm_install_theme skips download when same version present" {
    run in_sub "sddm_install_theme teal"
    : >"$CALLS"
    run in_sub "sddm_install_theme teal"
    [ "$status" -eq 0 ]
    run grep -c '^curl' "$CALLS"
    [ "$output" = "0" ]
}

@test "shell_set_zsh skips when already zsh" {
    printf '#!/bin/sh\necho "u:x:1:1::/h:/usr/bin/zsh"\n' >"$STUBS/getent"
    chmod +x "$STUBS/getent"
    run in_sub "shell_set_zsh"
    [ "$status" -eq 0 ]
    run grep -c '^chsh' "$CALLS"
    [ "$output" = "0" ]
}

@test "shell_set_zsh changes shell when bash" {
    printf '#!/bin/sh\necho "u:x:1:1::/h:/bin/bash"\n' >"$STUBS/getent"
    chmod +x "$STUBS/getent"
    run in_sub "shell_set_zsh"
    [ "$status" -eq 0 ]
    grep -q 'chsh -s /usr/bin/zsh' "$CALLS"
}

@test "services_enable adds VM daemons for vm and tolerates user unit failure" {
    printf '#!/bin/sh\necho "systemctl $*" >>"$CALLS"\n[ "$1" = --global ] && exit 1\nexit 0\n' >"$STUBS/systemctl"
    run in_sub "answers_set GPU vm; services_enable"
    [ "$status" -eq 0 ]
    [[ "$output" != *"install failed"* ]]
    [[ "$output" == *"Could not enable user unit"* ]]
    grep -q 'systemctl enable sddm NetworkManager bluetooth power-profiles-daemon qemu-guest-agent' "$CALLS"
    grep -q 'systemctl --global enable wireplumber' "$CALLS"
}

@test "gtk_apply_settings skips without a session bus" {
    printf '#!/bin/sh\nexit 1\n' >"$STUBS/gsettings"
    chmod +x "$STUBS/gsettings"
    run in_sub "gtk_apply_settings mauve"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "gtk_apply_settings skips when gsettings works but there is no session bus" {
    # gsettings get answers from schema defaults without a bus; set would only warn and not persist.
    printf '#!/bin/sh\necho "gsettings $*" >>"$CALLS"\n' >"$STUBS/gsettings"
    chmod +x "$STUBS/gsettings"
    DBUS_SESSION_BUS_ADDRESS= run in_sub "gtk_apply_settings mauve"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
    [ "$(grep -c 'gsettings set' "$CALLS")" -eq 0 ]
}

@test "gtk_apply_settings sets values when gsettings works" {
    printf '#!/bin/sh\necho "gsettings $*" >>"$CALLS"\n' >"$STUBS/gsettings"
    chmod +x "$STUBS/gsettings"
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus run in_sub "gtk_apply_settings mauve"
    grep -q 'cursor-theme catppuccin-mocha-mauve-cursors' "$CALLS"
    grep -q 'color-scheme prefer-dark' "$CALLS"
}

@test "sddm_install_theme dies on checksum mismatch and installs nothing" {
    HASH_TEAL=deadbeef run in_sub "sddm_install_theme teal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]]
    [ ! -e "$NUSKU_SDDM_THEMES/catppuccin-mocha-teal" ]
}

@test "every accent has a pinned sha256" {
    run in_sub 'for a in "${NUSKU_ACCENTS[@]}"; do [[ "${SDDM_THEME_SHA256[$a]:-}" =~ ^[0-9a-f]{64}$ ]] || echo "missing $a"; done'
    [ -z "$output" ]
}

@test "every accent maps to a Papirus folder colour" {
    run in_sub 'for a in "${NUSKU_ACCENTS[@]}"; do papirus_folder_color "$a"; done | sort -u | tr "\n" " "'
    [ "$output" = "blue cyan green indigo magenta orange paleorange pink red teal violet yellow " ]
}

@test "papirus_folders_apply recolours Papirus-Dark with sudo" {
    printf '#!/bin/sh\necho "papirus-folders $*" >>"$CALLS"\n' >"$STUBS/papirus-folders"
    chmod +x "$STUBS/papirus-folders"
    run in_sub 'papirus_folders_apply mauve'
    [ "$status" -eq 0 ]
    grep -qxF 'sudo papirus-folders -C violet --theme Papirus-Dark' "$CALLS"
}

@test "papirus_folders_apply without papirus-folders only warns" {
    run in_sub 'command() { [ "${2:-}" = papirus-folders ] && return 1; builtin command "$@"; }; papirus_folders_apply blue'
    [ "$status" -eq 0 ]
    ! grep -q papirus-folders "$CALLS" || false
}
