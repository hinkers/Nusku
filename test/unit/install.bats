# install.sh argument handling (the full run is covered by test/run-container-install.sh).

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP NUSKU_RUN_ID
}

@test "--help prints usage and exits 0 without creating a log" {
    run ./install.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: ./install.sh"* ]]
    [[ "$output" == *"--reconfigure"* ]]
    [ ! -d "$XDG_STATE_HOME/nusku" ]
}

@test "unknown option exits 2" {
    run ./install.sh --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
}

@test "--answers without a file exits 2" {
    run ./install.sh --answers
    [ "$status" -eq 2 ]
}

@test "--reconfigure with --update is rejected" {
    run ./install.sh --reconfigure --update
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot be combined"* ]]
}

@test "nusku-update pulls then runs install.sh --update" {
    fake="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$fake/scripts" "$BATS_TEST_TMPDIR/bin"
    cp scripts/nusku-update "$fake/scripts/"
    printf '#!/usr/bin/env bash\necho "install $*"\n' >"$fake/install.sh"
    printf '#!/usr/bin/env bash\necho "git $*"\n' >"$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$fake/install.sh" "$BATS_TEST_TMPDIR/bin/git" "$fake/scripts/nusku-update"
    ln -s "$fake/scripts/nusku-update" "$BATS_TEST_TMPDIR/nusku-update"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$BATS_TEST_TMPDIR/nusku-update"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "git -C $fake pull --ff-only" ]
    [ "${lines[1]}" = "install --update" ]
}
