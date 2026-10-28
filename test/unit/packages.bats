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
    PATH="$STUBS:$PATH" CALLS="$CALLS" bash -c 'source lib/log.sh; source lib/answers.sh; source lib/packages.sh; '"$1"
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
