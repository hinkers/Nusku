# bats' own `run` clashes with Nusku's, so Nusku code runs via bash -c.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE
    F="$BATS_TEST_TMPDIR/a.answers"
}

# Run a snippet with log, answers and ui libs sourced.
in_sub() {
    bash -c 'source lib/log.sh; source lib/answers.sh; source lib/ui.sh; '"$1"
}

@test "load/get round-trip" {
    printf 'GPU=vm\nACCENT=mauve\n' >"$F"
    run in_sub "answers_load '$F'; answers_get ACCENT"
    [ "$status" -eq 0 ]
    [ "$output" = "mauve" ]
}

@test "get of unset key prints empty" {
    run in_sub "answers_get NOPE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "comments and blank lines ignored" {
    printf '# a comment\n\nGPU=vm\n   \n# ACCENT=red\n' >"$F"
    run in_sub "answers_load '$F'; echo \"[\$(answers_get GPU)][\$(answers_get ACCENT)]\""
    [ "$output" = "[vm][]" ]
}

@test "unknown keys are warned and ignored" {
    printf 'BOGUS=1\nGPU=vm\n' >"$F"
    run in_sub "answers_load '$F'; echo \"[\$(answers_get BOGUS)][\$(answers_get GPU)]\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"BOGUS"* ]]
    [[ "$output" == *"[][vm]"* ]]
}

@test "save then load reproduces values" {
    run in_sub "answers_set GPU amd; answers_set ACCENT teal; answers_set APPS 'a b'; answers_save '$F.out'
        unset NUSKU_ANSWERS; declare -gA NUSKU_ANSWERS=(); answers_load '$F.out'
        echo \"\$(answers_get GPU)|\$(answers_get ACCENT)|\$(answers_get APPS)\""
    [ "$status" -eq 0 ]
    [ "$output" = "amd|teal|a b" ]
}

@test "save creates parent directories" {
    run in_sub "answers_set GPU vm; answers_save '$BATS_TEST_TMPDIR/x/y/answers'"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/x/y/answers" ]
}

@test "value with = sign preserved" {
    printf 'APPS=a=b\n' >"$F"
    run in_sub "answers_load '$F'; answers_get APPS"
    [ "$output" = "a=b" ]
}

@test "file is not executed" {
    printf 'GPU=$(touch %s/pwned)\n' "$BATS_TEST_TMPDIR" >"$F"
    run in_sub "answers_load '$F'"
    [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "validate accepts a good file" {
    printf 'GPU=hybrid-intel\nNVIDIA_MODULE=open\nAUR_HELPER=yay\nACCENT=blue\nTEST_AUTOLOGIN=1\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 0 ]
}

@test "validate rejects unknown accent" {
    printf 'GPU=vm\nAUR_HELPER=paru\nACCENT=purple\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *ACCENT* ]]
    [[ "$output" == *rosewater* ]]
}

@test "validate rejects unknown GPU" {
    printf 'GPU=voodoo\nAUR_HELPER=paru\nACCENT=blue\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *GPU* ]]
    [[ "$output" == *hybrid-amd* ]]
}

@test "validate rejects unknown AUR_HELPER and TEST_AUTOLOGIN" {
    printf 'GPU=vm\nAUR_HELPER=aura\nACCENT=blue\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *AUR_HELPER* ]]
    printf 'GPU=vm\nAUR_HELPER=yay\nACCENT=blue\nTEST_AUTOLOGIN=2\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *TEST_AUTOLOGIN* ]]
}

@test "validate requires missing keys" {
    printf 'GPU=vm\nACCENT=blue\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *AUR_HELPER* ]]
}

@test "validate requires NVIDIA_MODULE for nvidia and hybrid-*" {
    for g in nvidia hybrid-intel hybrid-amd; do
        printf 'GPU=%s\nAUR_HELPER=paru\nACCENT=blue\n' "$g" >"$F"
        run in_sub "answers_load '$F'; answers_validate"
        [ "$status" -eq 1 ]
        [[ "$output" == *NVIDIA_MODULE* ]]
        printf 'GPU=%s\nNVIDIA_MODULE=proprietary\nAUR_HELPER=paru\nACCENT=blue\n' "$g" >"$F"
        run in_sub "answers_load '$F'; answers_validate"
        [ "$status" -eq 0 ]
    done
}

@test "validate rejects bad NVIDIA_MODULE" {
    printf 'GPU=nvidia\nNVIDIA_MODULE=nouveau\nAUR_HELPER=paru\nACCENT=blue\n' >"$F"
    run in_sub "answers_load '$F'; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *NVIDIA_MODULE* ]]
}

@test "ui_choose returns stored answer without gum" {
    printf 'GPU=vm\n' >"$F"
    run env PATH="/usr/bin:/bin" NUSKU_NONINTERACTIVE=1 bash -c \
        "! command -v gum >/dev/null; source lib/log.sh; source lib/answers.sh; source lib/ui.sh; answers_load '$F'; ui_choose GPU 'GPU?' amd amd intel vm"
    [ "$status" -eq 0 ]
    [ "$output" = "vm" ]
}

@test "ui_choose returns stored answer interactively without prompting" {
    run in_sub "answers_set ACCENT red; ui_choose ACCENT 'Accent?' blue blue red"
    [ "$status" -eq 0 ]
    [ "$output" = "red" ]
}

@test "ui_choose non-interactive missing key dies" {
    run env NUSKU_NONINTERACTIVE=1 bash -c \
        "source lib/log.sh; source lib/answers.sh; source lib/ui.sh; ui_choose GPU 'GPU?' amd amd intel"
    [ "$status" -eq 1 ]
    [[ "$output" == *"answers file missing GPU"* ]]
}

@test "ui_checklist and ui_confirm honour non-interactive mode" {
    run env NUSKU_NONINTERACTIVE=1 bash -c \
        "source lib/log.sh; source lib/answers.sh; source lib/ui.sh; answers_set APPS 'a b'; ui_checklist APPS 'Apps?' a,b a b c"
    [ "$status" -eq 0 ]
    [ "$output" = "a b" ]
    run env NUSKU_NONINTERACTIVE=1 bash -c \
        "source lib/log.sh; source lib/answers.sh; source lib/ui.sh; ui_checklist APPS 'Apps?' a,b a b c"
    [ "$status" -eq 1 ]
    [[ "$output" == *"answers file missing APPS"* ]]
}

@test "ui_confirm non-interactive returns 0 without gum" {
    run env NUSKU_NONINTERACTIVE=1 bash -c \
        "source lib/log.sh; source lib/answers.sh; source lib/ui.sh; ui_confirm 'Go?'"
    [ "$status" -eq 0 ]
}

@test "interactive ui_choose stores gum result" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho picked\n' >"$BATS_TEST_TMPDIR/bin/gum"
    chmod +x "$BATS_TEST_TMPDIR/bin/gum"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
        "source lib/log.sh; source lib/answers.sh; source lib/ui.sh; ui_choose X 'q' d d picked >/dev/null; answers_get X"
    [ "$output" = "picked" ]
}
