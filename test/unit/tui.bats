# lib/tui.sh: key reading, single choice and the folding tree, with keys fed from a file.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    unset NUSKU_LOG NUSKU_STEP
    export NUSKU_TUI_IN="$BATS_TEST_TMPDIR/keys" NUSKU_TUI_OUT="$BATS_TEST_TMPDIR/screen"
}

tui() { bash -c 'set -Eeuo pipefail; source lib/log.sh; source lib/tui.sh; tui_open; '"$1"'; tui_close'; }

@test "keys: arrows, Home/End, PgUp/PgDn, space, enter, vim keys, Esc" {
    printf '\e[A\e[B\e[C\e[D\e[H\e[F\e[5~\e[6~ \nkjhl\e' >"$NUSKU_TUI_IN"
    run tui 'for i in $(seq 15); do tui_key; printf "%s " "$TUI_KEY"; done'
    [ "$status" -eq 0 ]
    [ "$output" = "up down right left home end pgup pgdn space enter up down left right esc " ]
}

@test "keys: running out of input is eof" {
    : >"$NUSKU_TUI_IN"
    run tui 'tui_key; echo "$TUI_KEY"'
    [ "$output" = eof ]
}

@test "keys: a key typed straight after Esc is not lost" {
    printf '\ej' >"$NUSKU_TUI_IN"
    run tui 'tui_key; printf "%s " "$TUI_KEY"; tui_key; echo "$TUI_KEY"'
    [ "$output" = "esc down" ]
}

@test "choose: starts on the current choice, Enter picks" {
    printf '\e[B\n' >"$NUSKU_TUI_IN"
    run tui 'tui_choose T S 1 a b c; echo "picked=$TUI_CHOICE"'
    [ "$output" = picked=2 ]
}

@test "choose: wraps around, Esc returns 1" {
    printf '\e[A\n' >"$NUSKU_TUI_IN"
    run tui 'tui_choose T S 0 a b c; echo "picked=$TUI_CHOICE"'
    [ "$output" = picked=2 ]
    printf '\e' >"$NUSKU_TUI_IN"
    run tui 'if tui_choose T S 0 a b c; then echo picked; else echo esc; fi'
    [ "$output" = esc ]
}

@test "menu: the cursor skips dividers" {
    printf '\e[B\e[B\n' >"$NUSKU_TUI_IN"
    run tui 'tui_menu T S H 0 one - two three; echo "picked=$TUI_CHOICE"'
    [ "$output" = picked=3 ]
}

@test "Ctrl+C cancels and gives the terminal back" {
    printf '\x03' >"$NUSKU_TUI_IN"
    run tui 'tui_choose T S 0 a b'
    [ "$status" -eq 1 ]
    [[ "$output" == *Cancelled* ]]
    # The screen ends by leaving the alternate screen with the cursor shown.
    [[ "$(tail -c 16 "$NUSKU_TUI_OUT" | od -c)" == *'?   2   5   h'* ]]
}

@test "the text console gets plain ASCII" {
    printf '\n' >"$NUSKU_TUI_IN"
    TERM=linux run tui 'tui_choose T S 0 a b'
    ! grep -q '❯\|●' "$NUSKU_TUI_OUT" || false
    grep -qF '> (*) a' <(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$NUSKU_TUI_OUT")
}

tree() {
    bash -c 'set -Eeuo pipefail; source lib/log.sh; source lib/tui.sh; tui_open
        TUI_T_KIND=(g i i g i) TUI_T_LABEL=(G1 a b G2 c) TUI_T_PARENT=("" 0 0 "" 3) TUI_T_ON=(0 1 0 0 0) TUI_T_OPEN=(0 0 0 0 0)
        if tui_tree T S; then r=done; else r=esc; fi; tui_close
        echo "$r on=${TUI_T_ON[*]} open=${TUI_T_OPEN[*]}"'
}

@test "tree: Space on a group ticks all, again clears all" {
    printf ' \e[F\n' >"$NUSKU_TUI_IN"
    run tree
    [ "$output" = "done on=0 1 1 0 0 open=0 0 0 0 0" ]
    printf '  \e[F\n' >"$NUSKU_TUI_IN"
    run tree
    [ "$output" = "done on=0 0 0 0 0 open=0 0 0 0 0" ]
}

@test "tree: folded items are skipped; Enter unfolds and Space ticks an item" {
    # Down from G1 (folded) lands on G2; open it, tick c.
    printf '\e[B\n\e[B \e[F\n' >"$NUSKU_TUI_IN"
    run tree
    [ "$output" = "done on=0 1 0 0 1 open=0 0 0 1 0" ]
}

@test "tree: Left on an item folds its group; Esc reports cancel" {
    printf '\e[C\e[B\e[D\e' >"$NUSKU_TUI_IN"
    run tree
    [ "$output" = "esc on=0 1 0 0 0 open=0 0 0 0 0" ]
}
