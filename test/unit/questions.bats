# lib/questions.sh: the settings menu, with keys fed from a file. Rows on a non-NVIDIA machine:
# Graphics, AUR helper, Accent colour, Apps, (divider), Install. Up from the top wraps to Install.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    unset NUSKU_LOG NUSKU_STEP
    export NUSKU_TUI_IN="$BATS_TEST_TMPDIR/keys" NUSKU_TUI_OUT="$BATS_TEST_TMPDIR/screen"
}

menu() {
    printf "$1" >"$NUSKU_TUI_IN"
    bash -c 'set -Eeuo pipefail; source lib/log.sh; source lib/answers.sh; source lib/tui.sh; source lib/apps.sh; source lib/questions.sh
        '"$2"'; questions_menu intel >/dev/null 2>&1
        for k in GPU NVIDIA_MODULE AUR_HELPER ACCENT APPS LANGS; do printf "%s=[%s] " "$k" "$(answers_get "$k")"; done'
}

screen() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$NUSKU_TUI_OUT"; }

@test "Install straight away takes the detected graphics and the defaults" {
    run menu '\e[A\n' ':'
    [ "$status" -eq 0 ]
    [ "$output" = "GPU=[intel] NVIDIA_MODULE=[] AUR_HELPER=[paru] ACCENT=[blue] APPS=[neovim gh claude-code firefox discord obsidian spotify vlc] LANGS=[] " ]
    screen | grep -qE 'Graphics +Intel graphics'
    screen | grep -qE 'Apps +8 usual picks'
}

@test "the detected graphics are marked in the list" {
    run menu '\n\e\e[A\n' ':'
    screen | grep -qF 'Intel graphics (detected)'
}

@test "picking NVIDIA adds the driver row; picking Intel again drops it" {
    # Graphics: intel (2nd) -> down to nvidia (3rd).
    run menu '\n\e[B\n\e[A\n' ':'
    [[ "$output" == "GPU=[nvidia] NVIDIA_MODULE=[open] "* ]]
    screen | grep -qE 'NVIDIA driver +open'
    run menu '\n\e[A\n\e[A\n' 'answers_set GPU nvidia; answers_set NVIDIA_MODULE proprietary'
    [[ "$output" == "GPU=[intel] NVIDIA_MODULE=[] "* ]]
}

@test "accent and AUR helper are changed in place" {
    # AUR helper (2nd row): paru -> yay. Accent (3rd row): blue (13th) -> sapphire (12th), then down twice to Install.
    run menu '\e[B\n\e[B\n\e[B\n\e[A\n\e[B\e[B\n' ':'
    [[ "$output" == *"AUR_HELPER=[yay] ACCENT=[sapphire] "* ]]
}

@test "saved answers are the starting point" {
    run menu '\e[A\n' 'answers_set GPU amd; answers_set ACCENT mauve; answers_set APPS gimp; answers_set LANGS go'
    [ "$output" = "GPU=[amd] NVIDIA_MODULE=[] AUR_HELPER=[paru] ACCENT=[mauve] APPS=[gimp] LANGS=[go] " ]
    screen | grep -qE 'Apps +1 app, 1 language$'
}

@test "Apps opens the app list from the menu" {
    # Apps is the 4th row; in the list, tick all of Dev's Languages group (2nd row), Done, Install.
    run menu '\e[B\e[B\e[B\n\e[B \e[F\n\e[B\n' ':'
    [[ "$output" == *"LANGS=[python php gdscript js rust go cpp csharp java lua] " ]]
}

@test "Esc asks first: Keep going stays, Quit cancels" {
    run menu '\e\n\e[A\n' ':'
    [ "$status" -eq 0 ]
    [[ "$output" == "GPU=[intel] "* ]]
    run menu '\e\e[B\n' ':'
    [ "$status" -eq 1 ]
}

@test "running out of input cancels instead of waiting forever" {
    run timeout 10 bash -c "$(declare -f menu); menu '' ':'"
    [ "$status" -eq 1 ]
}

@test "questions_needed: only when something is unanswered" {
    run bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; source lib/questions.sh
        questions_needed && echo need
        answers_set GPU intel; answers_set AUR_HELPER paru; answers_set ACCENT blue; answers_set APPS ""
        questions_needed || echo done
        answers_set GPU nvidia; questions_needed && echo need-driver
        answers_set NVIDIA_MODULE open; questions_needed || echo done-again'
    [ "$output" = $'need\ndone\nneed-driver\ndone-again' ]
}
