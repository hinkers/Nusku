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
