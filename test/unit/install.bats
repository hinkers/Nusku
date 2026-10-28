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

@test "invalid --answers dies before preflight touches the system" {
    stubs="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stubs"
    export SUDO_ARGS="$BATS_TEST_TMPDIR/sudo-args"
    : >"$SUDO_ARGS"
    printf '#!/usr/bin/env bash\necho "$*" >>"$SUDO_ARGS"\n' >"$stubs/sudo"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/curl"
    chmod +x "$stubs/sudo" "$stubs/curl"
    export NUSKU_ARCH_RELEASE="$BATS_TEST_TMPDIR/arch-release" NUSKU_EUID=1000
    : >"$NUSKU_ARCH_RELEASE"
    printf 'GPU=amd\nAUR_HELPER=paru\nACCENT=banana\n' >"$BATS_TEST_TMPDIR/bad.answers"
    PATH="$stubs:$PATH" run ./install.sh --answers "$BATS_TEST_TMPDIR/bad.answers" --no-reboot
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid ACCENT='banana'"* ]]
    [ "$(grep -c pacman "$SUDO_ARGS")" -eq 0 ]
}

@test "--update without saved answers dies before preflight" {
    stubs="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stubs"
    export SUDO_ARGS="$BATS_TEST_TMPDIR/sudo-args"
    : >"$SUDO_ARGS"
    printf '#!/usr/bin/env bash\necho "$*" >>"$SUDO_ARGS"\n' >"$stubs/sudo"
    chmod +x "$stubs/sudo"
    PATH="$stubs:$PATH" run ./install.sh --update --no-reboot
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs saved answers"* ]]
    [ ! -s "$SUDO_ARGS" ]
}

@test "--apps with --update exits 2" {
    run ./install.sh --apps --update
    [ "$status" -eq 2 ]
    [[ "$output" == *"--apps"* ]]
}

@test "--apps with --answers or --reconfigure exits 2" {
    run ./install.sh --apps --reconfigure
    [ "$status" -eq 2 ]
    run ./install.sh --apps --answers /nonexistent
    [ "$status" -eq 2 ]
}

@test "--apps without saved answers dies before preflight" {
    stubs="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stubs"
    export SUDO_ARGS="$BATS_TEST_TMPDIR/sudo-args"
    : >"$SUDO_ARGS"
    printf '#!/usr/bin/env bash\necho "$*" >>"$SUDO_ARGS"\n' >"$stubs/sudo"
    chmod +x "$stubs/sudo"
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg" PATH="$stubs:$PATH" run ./install.sh --apps --no-reboot
    [ "$status" -ne 0 ]
    [[ "$output" == *"--apps needs saved answers ($BATS_TEST_TMPDIR/cfg/nusku/answers)"* ]]
    [[ "$output" == *"./install.sh"* ]]
    [ ! -s "$SUDO_ARGS" ]
}

@test "help lists --apps" {
    run ./install.sh --help
    [[ "$output" == *"--apps"*"Change which optional apps and languages are installed, then re-apply."* ]]
}
