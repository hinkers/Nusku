setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE NUSKU_RUN_ID
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\nexec "$@"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
}

in_sub() {
    PATH="$STUBS:$PATH" CALLS="$CALLS" bash -c 'source lib/log.sh; source lib/backup.sh; '"$1"
}

@test "backup_file copies a home file keeping its relative path" {
    mkdir -p "$HOME/.config/x"
    echo hi >"$HOME/.config/x/a.conf"
    run in_sub "backup_file '$HOME/.config/x/a.conf'"
    [ "$status" -eq 0 ]
    f="$(ls -d "$XDG_STATE_HOME"/nusku/backup-*)/.config/x/a.conf"
    [ "$(cat "$f")" = "hi" ]
    [ "$(grep -c '^sudo' "$CALLS")" -eq 0 ]
}

@test "backup_file copies a system file under its absolute path via sudo" {
    echo sys >"$BATS_TEST_TMPDIR/sysfile"
    run in_sub "backup_file '$BATS_TEST_TMPDIR/sysfile'"
    [ "$status" -eq 0 ]
    f="$(ls -d "$XDG_STATE_HOME"/nusku/backup-*)${BATS_TEST_TMPDIR}/sysfile"
    [ "$(cat "$f")" = "sys" ]
    grep -q '^sudo cp -a' "$CALLS"
    grep -q '^sudo chown' "$CALLS"
}

@test "backup_file on a missing path does nothing and creates no dir" {
    run in_sub "backup_file '$HOME/nope'"
    [ "$status" -eq 0 ]
    [ ! -d "$XDG_STATE_HOME/nusku" ]
}

@test "backup dir is created only on first use" {
    echo a >"$HOME/a"
    run in_sub "true"
    [ ! -d "$XDG_STATE_HOME/nusku" ]
    run in_sub "backup_file '$HOME/a'"
    [ -d "$XDG_STATE_HOME/nusku" ]
}

@test "same run id gives the same dir across calls" {
    echo a >"$HOME/a"
    echo b >"$HOME/b"
    run in_sub "backup_file '$HOME/a'; sleep 1; backup_file '$HOME/b'; ls -d '$XDG_STATE_HOME'/nusku/backup-* | wc -l"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "1" ]
    run in_sub "NUSKU_RUN_ID=fixed; [ \"\$(backup_dir)\" = '$XDG_STATE_HOME/nusku/backup-fixed' ]"
    [ "$status" -eq 0 ]
}
