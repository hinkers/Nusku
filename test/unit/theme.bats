bats_require_minimum_version 1.5.0

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP
}

in_sub() {
    bash -c 'source lib/log.sh; source lib/answers.sh; source lib/theme.sh; '"$1"
}

@test "palette has 26 colours" {
    run grep -cE '^[a-z0-9]+=[0-9a-f]{6}$' theme/palette.conf
    [ "$output" = "26" ]
}

@test "blue is 89b4fa" {
    run in_sub "theme_load theme/palette.conf blue; echo \"\${NUSKU_COLORS[blue]} \${NUSKU_COLORS[accent]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "89b4fa 89b4fa" ]
}

@test "render replaces {{base}} and {{accent}}" {
    printf 'b={{base}} a={{accent}} n={{accent_name}}\n' >"$BATS_TEST_TMPDIR/t.tmpl"
    run in_sub "theme_load theme/palette.conf mauve; theme_render '$BATS_TEST_TMPDIR/t.tmpl' '$BATS_TEST_TMPDIR/o'"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/o")" = "b=1e1e2e a=cba6f7 n=mauve" ]
}

@test "render {{accent_rgb}} gives 137, 180, 250 for blue" {
    printf '{{accent_rgb}}|{{base_rgb}}\n' >"$BATS_TEST_TMPDIR/t.tmpl"
    run in_sub "theme_load theme/palette.conf blue; theme_render '$BATS_TEST_TMPDIR/t.tmpl' '$BATS_TEST_TMPDIR/o'"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/o")" = "137, 180, 250|30, 30, 46" ]
}

@test "unknown placeholder dies naming it" {
    printf 'x {{nope}}\n' >"$BATS_TEST_TMPDIR/t.tmpl"
    run in_sub "theme_load theme/palette.conf blue; theme_render '$BATS_TEST_TMPDIR/t.tmpl' '$BATS_TEST_TMPDIR/o'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"nope"* ]]
}

@test "invalid accent dies" {
    run in_sub "theme_load theme/palette.conf banana"
    [ "$status" -ne 0 ]
    [[ "$output" == *"banana"* ]]
}

@test "render_all writes every template output" {
    run in_sub "answers_set ACCENT teal; theme_render_all '$PWD'"
    [ "$status" -eq 0 ]
    n_tmpl="$(find theme/templates -maxdepth 1 -name '*.tmpl' | wc -l)"
    n_out="$(find "$XDG_CONFIG_HOME/nusku/theme" -maxdepth 1 -type f | wc -l)"
    [ "$n_tmpl" -ge 6 ]
    [ "$n_out" = "$n_tmpl" ]
    grep -q '94e2d5' "$XDG_CONFIG_HOME/nusku/theme/colors.css"
    run grep -r '{{' "$XDG_CONFIG_HOME/nusku/theme"
    [ "$status" -ne 0 ]
}

make_repo() {
    R="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$R/theme/templates/home/.config/app" "$R/theme/templates/home/.local"
    cp theme/palette.conf "$R/theme/"
    printf 'accent={{accent}}\n' >"$R/theme/templates/top.conf.tmpl"
    printf 'accent={{accent}}\n' >"$R/theme/templates/home/.config/app/c.css.tmpl"
    printf 'plain {{notatemplate}}\n' >"$R/theme/templates/home/.local/raw.txt"
}

@test "render_all renders home templates under HOME and copies plain files" {
    make_repo
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.config/app/c.css")" = "accent=f38ba8" ]
    [ "$(cat "$HOME/.local/raw.txt")" = "plain {{notatemplate}}" ]
    [ -f "$XDG_CONFIG_HOME/nusku/theme/top.conf" ]
    # re-render overwrites a previously rendered regular file
    run in_sub "answers_set ACCENT blue; theme_render_all '$R'"
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.config/app/c.css")" = "accent=89b4fa" ]
}

@test "render_all dies when a home output is a symlink" {
    make_repo
    mkdir -p "$HOME/.config/app"
    printf 'x' >"$BATS_TEST_TMPDIR/target"
    ln -s "$BATS_TEST_TMPDIR/target" "$HOME/.config/app/c.css"
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"c.css"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/target")" = "x" ]
}

@test "render_all dies when a home output is a directory" {
    make_repo
    mkdir -p "$HOME/.config/app/c.css"
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"c.css"* ]]
}

@test "nusku-theme rejects bad accent and saves a good one" {
    run bash scripts/nusku-theme banana
    [ "$status" -ne 0 ]
    run bash scripts/nusku-theme sky
    [ "$status" -eq 0 ]
    grep -q '^ACCENT=sky$' "$XDG_CONFIG_HOME/nusku/answers"
    grep -q '74c7ec' "$XDG_CONFIG_HOME/nusku/theme/colors.css"
}
