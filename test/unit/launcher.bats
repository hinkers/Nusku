# Launcher tweaks: lib/launcher.sh against fake system and user application dirs.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" XDG_DATA_HOME="$BATS_TEST_TMPDIR/user"
    unset NUSKU_LOG NUSKU_STEP
    SYS="$BATS_TEST_TMPDIR/sys"
    mkdir -p "$SYS/applications"
    export NUSKU_LAUNCHER_DIRS="$SYS"
    USER_APPS="$XDG_DATA_HOME/applications"
    LIST="$BATS_TEST_TMPDIR/overrides.list"
    printf '# test\nhide clutter.desktop\nicon odd.desktop papirus-name   # comment\nhide absent.desktop\n' >"$LIST"
    printf '[Desktop Entry]\nName=Clutter\nIcon=c\n' >"$SYS/applications/clutter.desktop"
    printf '[Desktop Entry]\nName=Odd\nIcon=odd\n\n[Desktop Action new]\nName=New\nIcon=keep\n' >"$SYS/applications/odd.desktop"
}

apply() {
    bash -c 'source lib/log.sh; source lib/launcher.sh; launcher_apply "$1"' _ "$LIST"
}

@test "hide adds NoDisplay; icon swaps only the main section's icon" {
    run apply
    [ "$status" -eq 0 ]
    grep -qx 'NoDisplay=true' "$USER_APPS/clutter.desktop"
    grep -qx 'Icon=papirus-name' "$USER_APPS/odd.desktop"
    grep -qx 'Icon=keep' "$USER_APPS/odd.desktop"
    [ ! -e "$USER_APPS/absent.desktop" ]
}

@test "re-running gives the same files" {
    apply
    cp "$USER_APPS/odd.desktop" "$BATS_TEST_TMPDIR/first"
    apply
    cmp "$USER_APPS/odd.desktop" "$BATS_TEST_TMPDIR/first"
    [ "$(grep -c '^X-Nusku-Override=true$' "$USER_APPS/odd.desktop")" -eq 1 ]
}

@test "the user's own entry is never touched" {
    mkdir -p "$USER_APPS"
    printf '[Desktop Entry]\nName=Mine\n' >"$USER_APPS/clutter.desktop"
    apply
    [ "$(cat "$USER_APPS/clutter.desktop")" = "$(printf '[Desktop Entry]\nName=Mine')" ]
}

@test "managed entries are removed when the app or the list line goes" {
    apply
    rm "$SYS/applications/clutter.desktop"
    printf 'hide clutter.desktop\n' >"$LIST"
    apply
    [ ! -e "$USER_APPS/clutter.desktop" ]
    [ ! -e "$USER_APPS/odd.desktop" ]
}

@test "the shipped list parses and every line is hide or icon" {
    run awk '!/^[[:space:]]*(#|$)/ && $1 != "hide" && $1 != "icon"' config/applications/overrides.list
    [ -z "$output" ]
}
