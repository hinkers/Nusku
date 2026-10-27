# bats' own `run` clashes with Nusku's, so Nusku code runs via bash -c.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP
}

# Run a snippet with lib/log.sh sourced (optionally under set -e).
in_sub() {
    bash -c 'source lib/log.sh; log_init; '"$1"
}

@test "log_init creates the log file under XDG_STATE_HOME" {
    in_sub 'log_info hi; echo "$NUSKU_LOG" >"$BATS_TEST_TMPDIR/path"'
    path="$(cat "$BATS_TEST_TMPDIR/path")"
    [[ "$path" == "$BATS_TEST_TMPDIR"/nusku/install-*.log ]]
    [ -f "$path" ]
    grep -q hi "$path"
}

@test "log_* work without an explicit log_init" {
    bash -c 'source lib/log.sh; log_warn lazy; run true'
    compgen -G "$BATS_TEST_TMPDIR/nusku/install-*.log"
    grep -q lazy "$BATS_TEST_TMPDIR"/nusku/install-*.log
}

@test "run passes through success" {
    run in_sub 'run true'
    [ "$status" -eq 0 ]
}

@test "run passes through success under set -e" {
    run bash -c 'set -e; source lib/log.sh; log_init; run true; echo after'
    [ "$status" -eq 0 ]
    [[ "$output" == *after* ]]
}

@test "run failure names step, command and log" {
    run in_sub 'step "Install packages"; run false'
    [ "$status" -eq 1 ]
    [[ "$output" == *"step: Install packages"* ]]
    [[ "$output" == *"command failed: false"* ]]
    [[ "$output" == *"Full log:"* ]]
}

@test "run failure exits under set -e too" {
    run bash -c 'set -e; source lib/log.sh; log_init; run false; echo notreached'
    [ "$status" -eq 1 ]
    [[ "$output" != *notreached* ]]
}

@test "run does not change the caller's pipefail" {
    run bash -c 'source lib/log.sh; log_init; set +o pipefail; run true; [[ $- != *x* ]]; set -o | grep -q "pipefail.*off"'
    [ "$status" -eq 0 ]
}

@test "run captures command output in log" {
    in_sub 'run echo marker123; echo "$NUSKU_LOG" >"$BATS_TEST_TMPDIR/path"'
    grep -q marker123 "$(cat "$BATS_TEST_TMPDIR/path")"
}

@test "log file never contains ANSI escapes" {
    in_sub 'log_error boom; log_warn w; run echo x; echo "$NUSKU_LOG" >"$BATS_TEST_TMPDIR/path"'
    ! grep -q $'\033' "$(cat "$BATS_TEST_TMPDIR/path")"
}
