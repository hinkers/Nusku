# nusku-fetch (fastfetch greeting, optional Pokemon logo) and its config. Stubs on PATH.

bats_require_minimum_version 1.5.0

setup() {
    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    export FF_ARGS="$BATS_TEST_TMPDIR/ff-args"
    export KR_ARGS="$BATS_TEST_TMPDIR/kr-args"
    : >"$FF_ARGS"
    : >"$KR_ARGS"
    cat >"$STUBS/fastfetch" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf 'ARG<%s>\n' "$a"; done >>"$FF_ARGS"
echo "fastfetch ran"
STUB
    chmod +x "$STUBS/fastfetch"
    # Minimal PATH (stubs + coreutils only) so a real krabby on the host never leaks in.
    export PATH="$STUBS:/usr/bin:/bin"
}

krabby_stub() { # $1 = shell body
    printf '#!/usr/bin/env bash\necho "$*" >>"$KR_ARGS"\n%s\n' "$1" >"$STUBS/krabby"
    chmod +x "$STUBS/krabby"
}

@test "pokemon is a System tools app, not starred" {
    run bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; apps_in_group system'
    [ "$status" -eq 0 ]
    [[ "$output" == *pokemon* ]]
    run bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; apps_label pokemon; apps_starred'
    [[ "$output" == *"Pokémon in fastfetch"* ]]
    [[ "$output" != *pokemon* ]]
}

@test "APPS=pokemon installs krabby-bin from the AUR" {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    run bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; answers_set APPS pokemon; apps_batches'
    [ "$status" -eq 0 ]
    [ "$output" = "aur pokemon krabby-bin" ]
}

@test "nusku-fetch gives fastfetch the krabby sprite as raw logo data" {
    krabby_stub 'printf "pikachu\n\033[33mSPRITE\033[0m\n"'
    run scripts/nusku-fetch
    [ "$status" -eq 0 ]
    [ "$output" = "fastfetch ran" ]
    grep -qx 'random 1-3' "$KR_ARGS"
    grep -qx 'ARG<--data-raw>' "$FF_ARGS"
    grep -qF 'SPRITE' "$FF_ARGS"
    grep -qF 'pikachu' "$FF_ARGS"
}

@test "nusku-fetch without krabby runs plain fastfetch, silently" {
    run --separate-stderr scripts/nusku-fetch
    [ "$status" -eq 0 ]
    [ "$output" = "fastfetch ran" ]
    [ -z "$stderr" ]
    [ ! -s "$FF_ARGS" ]
}

@test "nusku-fetch falls back to plain fastfetch when krabby fails" {
    krabby_stub 'echo "boom" >&2; echo partial; exit 3'
    run --separate-stderr scripts/nusku-fetch
    [ "$status" -eq 0 ]
    [ "$output" = "fastfetch ran" ]
    [ -z "$stderr" ]
    [ ! -s "$FF_ARGS" ]
}

@test "nusku-fetch falls back to plain fastfetch when krabby prints nothing" {
    krabby_stub 'exit 0'
    run --separate-stderr scripts/nusku-fetch
    [ "$status" -eq 0 ]
    [ "$output" = "fastfetch ran" ]
    [ -z "$stderr" ]
    [ ! -s "$FF_ARGS" ]
}

@test "nusku-fetch does nothing, quietly, without fastfetch" {
    rm "$STUBS/fastfetch"
    run --separate-stderr scripts/nusku-fetch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "zshrc runs nusku-fetch before the prompt init, only if it exists" {
    grep -qE 'command -v nusku-fetch.*&& nusku-fetch' config/zsh/zshrc
    [ "$(grep -n 'nusku-fetch' config/zsh/zshrc | head -1 | cut -d: -f1)" -lt "$(grep -n 'starship init' config/zsh/zshrc | cut -d: -f1)" ]
}

@test "fastfetch config is valid JSONC with the original module list and icons" {
    grep -v '^[[:space:]]*//' config/fastfetch/config.jsonc | jq -e . >/dev/null
    run bash -c "grep -v '^[[:space:]]*//' config/fastfetch/config.jsonc | jq -r '[.modules[] | if type == \"object\" then .type else . end] | join(\" \")'"
    [ "$output" = "title separator os kernel uptime packages shell de wm terminal cpu gpu memory disk break colors" ]
    # every stats module carries a key icon
    run bash -c "grep -v '^[[:space:]]*//' config/fastfetch/config.jsonc | jq -r '[.modules[] | select(type == \"object\") | select((.key // \"\") == \"\")] | length'"
    [ "$output" = "0" ]
}
