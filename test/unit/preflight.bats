bats_require_minimum_version 1.5.0

# bats' own `run` clashes with Nusku's, so Nusku code runs via bash -c.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    export SUDO_ARGS="$BATS_TEST_TMPDIR/sudo-args"
    cat >"$STUBS/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SUDO_ARGS"
[ "$1" = "-n" ] && exit "${STUB_SUDO_N_RC:-${STUB_SUDO_RC:-0}}"
exit "${STUB_SUDO_RC:-0}"
STUB
    cat >"$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
exit "${STUB_CURL_RC:-0}"
STUB
    chmod +x "$STUBS/sudo" "$STUBS/curl"
    export PATH="$STUBS:$PATH"
    export NUSKU_ARCH_RELEASE="$BATS_TEST_TMPDIR/arch-release"
    : >"$NUSKU_ARCH_RELEASE"
    export NUSKU_EUID=1000
}

in_sub() {
    bash -c 'source lib/log.sh; source lib/preflight.sh; '"$1"
}

@test "fails when not Arch" {
    export NUSKU_ARCH_RELEASE="$BATS_TEST_TMPDIR/missing"
    run in_sub preflight_checks
    [ "$status" -ne 0 ]
    [[ "$output" == *"only supports Arch Linux"* ]]
}

@test "fails as root" {
    export NUSKU_EUID=0
    run in_sub preflight_checks
    [ "$status" -ne 0 ]
    [[ "$output" == *"not root"* ]]
}

@test "fails when sudo -v fails" {
    export STUB_SUDO_RC=1
    run in_sub preflight_checks
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs sudo access"* ]]
}

@test "passwordless sudo passes without sudo -v (verifypw needs NOPASSWD on every rule)" {
    export STUB_SUDO_N_RC=0 STUB_SUDO_RC=1
    run in_sub preflight_checks
    [ "$status" -eq 0 ]
    run ! grep -qx -- '-v' "$SUDO_ARGS"
}

@test "falls back to sudo -v when sudo needs a password" {
    export STUB_SUDO_N_RC=1
    run in_sub preflight_checks
    [ "$status" -eq 0 ]
    grep -qx -- '-v' "$SUDO_ARGS"
}

@test "fails with no network" {
    export STUB_CURL_RC=6
    run in_sub preflight_checks
    [ "$status" -ne 0 ]
    [[ "$output" == *"no network"* ]]
}

@test "passes when all ok" {
    run in_sub preflight_checks
    [ "$status" -eq 0 ]
    grep -qx -- '-n true' "$SUDO_ARGS"
}

@test "preflight_bootstrap runs a single full-upgrade pacman install" {
    run in_sub preflight_bootstrap
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$SUDO_ARGS")" -eq 1 ]
    [ "$(cat "$SUDO_ARGS")" = "pacman -Syu --needed --noconfirm gum jq git base-devel curl pciutils" ]
}
