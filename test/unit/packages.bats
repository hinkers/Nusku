# bats' own `run` clashes with Nusku's, so Nusku code runs via bash -c.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
}

in_sub() {
    NUSKU_ROOT="$PWD" PATH="$STUBS:$PATH" CALLS="$CALLS" bash -c 'source lib/log.sh; source lib/answers.sh; source lib/backup.sh; source lib/apps.sh; source lib/packages.sh; '"$1"
}

@test "pkg_read_list strips comments and blanks" {
    printf '# header\nfoo\n\n  bar  # why\n   # indented comment\nbaz\n' >"$BATS_TEST_TMPDIR/a.list"
    run in_sub "pkg_read_list '$BATS_TEST_TMPDIR/a.list'"
    [ "$status" -eq 0 ]
    [ "$output" = $'foo\nbar\nbaz' ]
}

@test "pkg_read_list merges and dedupes two files" {
    printf 'foo\nbar\n' >"$BATS_TEST_TMPDIR/a.list"
    printf 'bar\nbaz\n' >"$BATS_TEST_TMPDIR/b.list"
    run in_sub "pkg_read_list '$BATS_TEST_TMPDIR/a.list' '$BATS_TEST_TMPDIR/b.list'"
    [ "$output" = $'foo\nbar\nbaz' ]
}

@test "pkg_install_repo calls pacman with --needed" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    run in_sub "pkg_install_repo foo bar"
    [ "$status" -eq 0 ]
    grep -q 'sudo pacman -S --needed --noconfirm foo bar' "$CALLS"
}

@test "pkg_install_repo with no names does nothing" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    run in_sub "pkg_install_repo"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "pkg_install_aur uses the chosen helper" {
    printf '#!/bin/sh\necho "yay $*" >>"$CALLS"\n' >"$STUBS/yay"
    chmod +x "$STUBS/yay"
    run in_sub "answers_set AUR_HELPER yay; pkg_install_aur foo"
    [ "$status" -eq 0 ]
    grep -q 'yay -S --needed --noconfirm foo' "$CALLS"
}

@test "aur_bootstrap skips when helper present" {
    printf '#!/bin/sh\nexit 0\n' >"$STUBS/paru"
    printf '#!/bin/sh\necho "git $*" >>"$CALLS"\n' >"$STUBS/git"
    chmod +x "$STUBS/paru" "$STUBS/git"
    run in_sub "aur_bootstrap paru"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "aur_bootstrap rejects unknown helper" {
    run in_sub "aur_bootstrap evil"
    [ "$status" -ne 0 ]
}

@test "pkg_read_list fails on a missing file and names it" {
    run in_sub "pkgs=\$(pkg_read_list '$BATS_TEST_TMPDIR/nope.list') || exit 7; echo \"not reached: \$pkgs\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"nope.list"* ]]
    [[ "$output" != *"not reached"* ]]
}

@test "aur_bootstrap clones the -bin repo and runs makepkg" {
    printf '#!/bin/sh\necho "git $*" >>"$CALLS"\nfor last; do :; done\nmkdir -p "$last"\n' >"$STUBS/git"
    fake_makepkg 'exit 0'
    chmod +x "$STUBS/git"
    run in_sub "aur_bootstrap yay"
    [ "$status" -eq 0 ]
    grep -q 'git clone https://aur.archlinux.org/yay-bin.git ' "$CALLS"
    grep -q 'makepkg -si --noconfirm' "$CALLS"
    [ "$(grep -c 'git clone' "$CALLS")" -eq 1 ]
}

# fake_makepkg BIN_BODY [SRC_BODY]: makepkg stub that "installs" $HELPER (default yay) whose
# body is BIN_BODY when building a -bin package and SRC_BODY (default exit 0) otherwise.
fake_makepkg() {
    cat >"$STUBS/makepkg" <<STUB
#!/bin/sh
echo "makepkg \$*" >>"\$CALLS"
case "\$(basename "\$PWD")" in
    *-bin) body='$1' ;;
    *) body='${2:-exit 0}' ;;
esac
name="\$(basename "\$PWD")"
printf '#!/bin/sh\n%s\n' "\$body" >"$STUBS/\${name%-bin}"
chmod +x "$STUBS/\${name%-bin}"
STUB
    chmod +x "$STUBS/makepkg"
}

@test "aur_bootstrap falls back to a source build when the -bin helper does not run" {
    printf '#!/bin/sh\necho "git $*" >>"$CALLS"\nfor last; do :; done\nmkdir -p "$last"\n' >"$STUBS/git"
    fake_makepkg 'exit 127'
    printf '#!/bin/sh\necho "pacman $*" >>"$CALLS"\n' >"$STUBS/pacman"
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/git" "$STUBS/pacman" "$STUBS/sudo"
    run in_sub "aur_bootstrap paru"
    [ "$status" -eq 0 ]
    grep -q 'git clone https://aur.archlinux.org/paru-bin.git ' "$CALLS"
    grep -q 'sudo pacman -Rdd --noconfirm paru-bin' "$CALLS"
    grep -q 'git clone https://aur.archlinux.org/paru.git ' "$CALLS"
    [[ "$output" == *"building it from source"* ]]
}

@test "aur_bootstrap rebuilds from source when an installed helper is broken" {
    printf '#!/bin/sh\nexit 127\n' >"$STUBS/paru"
    printf '#!/bin/sh\necho "git $*" >>"$CALLS"\nfor last; do :; done\nmkdir -p "$last"\n' >"$STUBS/git"
    fake_makepkg 'exit 127'
    printf '#!/bin/sh\nexit 1\n' >"$STUBS/pacman"
    chmod +x "$STUBS/paru" "$STUBS/git" "$STUBS/pacman"
    run in_sub "aur_bootstrap paru"
    [ "$status" -eq 0 ]
    grep -q 'git clone https://aur.archlinux.org/paru.git ' "$CALLS"
    [ "$(grep -c 'paru-bin' "$CALLS")" -eq 0 ]
}

@test "aur_bootstrap dies if the source-built helper still does not run" {
    printf '#!/bin/sh\necho "git $*" >>"$CALLS"\nfor last; do :; done\nmkdir -p "$last"\n' >"$STUBS/git"
    fake_makepkg 'exit 127' 'exit 127'
    printf '#!/bin/sh\nexit 1\n' >"$STUBS/pacman"
    chmod +x "$STUBS/git" "$STUBS/pacman"
    run in_sub "aur_bootstrap yay"
    [ "$status" -ne 0 ]
    [[ "$output" == *"still does not run"* ]]
}

# --- Optional apps: multilib, flatpak, soft installs -----------------------------------

# fake_sudo: logs the call, then really runs it (so stubbed pacman and a real install both work).
fake_sudo() {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n"$@"\n' >"$STUBS/sudo"
    printf '#!/bin/sh\necho "pacman $*" >>"$CALLS"\n' >"$STUBS/pacman"
    chmod +x "$STUBS/sudo" "$STUBS/pacman"
}

@test "pkg_enable_multilib uncomments only multilib" {
    fake_sudo
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    cat >"$BATS_TEST_TMPDIR/etc/pacman.conf" <<'CONF'
[core]
Include = /etc/pacman.d/mirrorlist

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
CONF
    export NUSKU_ETC="$BATS_TEST_TMPDIR/etc"
    run in_sub "pkg_enable_multilib"
    [ "$status" -eq 0 ]
    grep -qx '\[multilib\]' "$NUSKU_ETC/pacman.conf"
    grep -qx '#\[multilib-testing\]' "$NUSKU_ETC/pacman.conf"
    [ "$(grep -c '^#Include' "$NUSKU_ETC/pacman.conf")" -eq 1 ]
    [ "$(grep -c '^Include' "$NUSKU_ETC/pacman.conf")" -eq 2 ]
    [ "$(grep -A1 -x '\[multilib\]' "$NUSKU_ETC/pacman.conf" | tail -n1)" = "Include = /etc/pacman.d/mirrorlist" ]
    [ "$(grep -c '^pacman -Syu --noconfirm' "$CALLS")" -eq 1 ]
    : >"$CALLS"
    cp "$NUSKU_ETC/pacman.conf" "$BATS_TEST_TMPDIR/before"
    run in_sub "pkg_enable_multilib"
    [ "$status" -eq 0 ]
    cmp "$NUSKU_ETC/pacman.conf" "$BATS_TEST_TMPDIR/before"
    [ ! -s "$CALLS" ]
}

@test "pkg_enable_multilib appends the block when missing" {
    fake_sudo
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$BATS_TEST_TMPDIR/etc/pacman.conf"
    export NUSKU_ETC="$BATS_TEST_TMPDIR/etc"
    run in_sub "pkg_enable_multilib"
    [ "$status" -eq 0 ]
    [ "$(grep -A1 -x '\[multilib\]' "$NUSKU_ETC/pacman.conf" | tail -n1)" = "Include = /etc/pacman.d/mirrorlist" ]
    grep -q 'pacman -Syu --noconfirm' "$CALLS"
    [ "$(grep -c 'pacman -Sy ' "$CALLS")" -eq 0 ]
}

@test "pkg_flathub_remote and pkg_install_flatpak use the system installation" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    run in_sub "pkg_flathub_remote; pkg_install_flatpak com.x.App"
    [ "$status" -eq 0 ]
    grep -q 'sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$CALLS"
    grep -q 'sudo flatpak install --system -y --noninteractive flathub com.x.App' "$CALLS"
}

@test "a failing optional AUR app is recorded and the run continues" {
    printf '#!/bin/sh\necho "paru $*" >>"$CALLS"\ncase "$*" in *heroic-games-launcher-bin*) exit 1 ;; esac\n' >"$STUBS/paru"
    chmod +x "$STUBS/paru"
    run in_sub 'answers_set AUR_HELPER paru
        batches=$(printf "aur heroic heroic-games-launcher-bin\naur protonup protonup-qt\n")
        apps_install_aur_soft "$batches"
        echo "rc=$?"
        printf "F:%s\n" "${NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"F:Heroic Games Launcher: heroic-games-launcher-bin (AUR install failed)"* ]]
    [[ "$output" != *"F:ProtonUp"* ]]
    grep -q 'paru -S --needed --noconfirm heroic-games-launcher-bin' "$CALLS"
    grep -q 'paru -S --needed --noconfirm protonup-qt' "$CALLS"
}

@test "an app's AUR names go to the helper in one call" {
    printf '#!/bin/sh\necho "paru $*" >>"$CALLS"\n' >"$STUBS/paru"
    chmod +x "$STUBS/paru"
    run in_sub 'answers_set AUR_HELPER paru
        apps_install_aur_soft "$(printf "aur steam lib32-nvidia-580xx-utils\naur steam steam\n")"'
    [ "$status" -eq 0 ]
    [ "$(grep -c '^paru' "$CALLS")" -eq 1 ]
    grep -q 'paru -S --needed --noconfirm lib32-nvidia-580xx-utils steam' "$CALLS"
}

@test "a failing flatpak is recorded and the run continues" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\ncase "$*" in *remote-add*) ;; *com.bitwarden.desktop*) exit 1 ;; esac\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    run in_sub 'apps_install_flatpak_soft "$(printf "flatpak bitwarden com.bitwarden.desktop\nflatpak other org.o.App\n")"
        printf "F:%s\n" "${NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"F:Bitwarden"* ]]
    grep -q 'flatpak remote-add' "$CALLS"
    grep -q 'flathub org.o.App' "$CALLS"
}

@test "no flatpak lines means no flathub remote" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    run in_sub 'apps_install_flatpak_soft "$(printf "repo vlc\n")"'
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "rust is swapped for rustup with --ask=4" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    printf '#!/bin/sh\ncase "$*" in "-Qq rust") exit 0 ;; esac\nexit 1\n' >"$STUBS/pacman"
    chmod +x "$STUBS/sudo" "$STUBS/pacman"
    run in_sub "pkg_install_repo_swap_rust vlc rustup go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Replacing the rust package with rustup (needed for the Rust language option)"* ]]
    grep -q 'pacman -S --needed --noconfirm --ask=4 rustup' "$CALLS"
    grep -q 'pacman -S --needed --noconfirm vlc go$' "$CALLS"
    [ "$(grep -c 'rustup' "$CALLS")" -eq 1 ]
}

@test "rustup stays in the main batch when rust is not installed" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    printf '#!/bin/sh\nexit 1\n' >"$STUBS/pacman"
    chmod +x "$STUBS/sudo" "$STUBS/pacman"
    run in_sub "pkg_install_repo_swap_rust vlc rustup"
    [ "$status" -eq 0 ]
    grep -q 'pacman -S --needed --noconfirm vlc rustup$' "$CALLS"
    [ "$(grep -c -e '--ask=4' "$CALLS")" -eq 0 ]
}

@test "an already-installed flatpak is skipped, not reported as failed" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\nexit 1\n' >"$STUBS/sudo"
    printf '#!/bin/sh\ncase "$1" in info) exit 0 ;; esac\nexit 1\n' >"$STUBS/flatpak"
    chmod +x "$STUBS/sudo" "$STUBS/flatpak"
    run in_sub 'apps_install_flatpak_soft "$(printf "flatpak bitwarden com.bitwarden.desktop\n")"
        echo "n=${#NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"n=0"* ]]
    [[ "$output" == *"already installed"* ]]
    [ "$(grep -c 'flatpak install' "$CALLS")" -eq 0 ]
}

@test "a flatpak that is not installed yet still installs" {
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n' >"$STUBS/sudo"
    printf '#!/bin/sh\nexit 1\n' >"$STUBS/flatpak"
    chmod +x "$STUBS/sudo" "$STUBS/flatpak"
    run in_sub 'pkg_install_flatpak com.x.App'
    [ "$status" -eq 0 ]
    grep -q 'sudo flatpak install --system -y --noninteractive flathub com.x.App' "$CALLS"
}
