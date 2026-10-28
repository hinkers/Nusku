bats_require_minimum_version 1.5.0

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP
}

in_sub() {
    bash -c 'source lib/log.sh; source lib/answers.sh; source lib/backup.sh; source lib/theme.sh; '"$1"
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
    n_out="$(find "$XDG_CONFIG_HOME/nusku/theme" -maxdepth 1 -type f ! -name '.*' | wc -l)"
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

@test "pre-existing user file is backed up once, not on re-render" {
    make_repo
    mkdir -p "$HOME/.config/app"
    printf 'mine\n' >"$HOME/.config/app/c.css"
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.config/app/c.css")" = "accent=f38ba8" ]
    b="$(find "$XDG_STATE_HOME/nusku" -path '*backup-*/.config/app/c.css')"
    [ -n "$b" ]
    [ "$(cat "$b")" = "mine" ]
    rm -rf "$XDG_STATE_HOME"/nusku/backup-*
    run in_sub "answers_set ACCENT blue; theme_render_all '$R'"
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.config/app/c.css")" = "accent=89b4fa" ]
    [ -z "$(find "$XDG_STATE_HOME/nusku" -path '*backup-*' -type f)" ]
}

@test "render_all dies when a parent directory is a symlink" {
    make_repo
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.config"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.config/app"
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -ne 0 ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/elsewhere")" ]
}

@test "pre-pass failure leaves earlier targets untouched" {
    make_repo
    printf 'accent={{accent}}\n' >"$R/theme/templates/home/.a-first.tmpl"
    mkdir -p "$HOME/.config/app/c.css"
    printf 'keep\n' >"$HOME/.a-first"
    run in_sub "answers_set ACCENT red; theme_render_all '$R'"
    [ "$status" -ne 0 ]
    [ "$(cat "$HOME/.a-first")" = "keep" ]
    [ ! -e "$XDG_CONFIG_HOME/nusku/theme/top.conf" ]
}

@test "render_all renders Kvantum theme, cursor env and GTK settings for the accent" {
    run in_sub "answers_set ACCENT mauve; theme_render_all '$PWD'"
    [ "$status" -eq 0 ]
    kv="$HOME/.config/Kvantum"
    grep -qx 'theme=catppuccin-mocha-nusku' "$kv/kvantum.kvconfig"
    run grep -rn '^#' "$kv" --include='*.kvconfig'
    [ "$status" -ne 0 ]
    [ -s "$kv/catppuccin-mocha-nusku/catppuccin-mocha-nusku.kvconfig" ]
    grep -qi 'cba6f7' "$kv/catppuccin-mocha-nusku/catppuccin-mocha-nusku.svg"
    run grep -qi '89b4fa' "$kv/catppuccin-mocha-nusku/catppuccin-mocha-nusku.svg"
    [ "$status" -ne 0 ]
    grep -qi 'highlight.color=#cba6f7' "$kv/catppuccin-mocha-nusku/catppuccin-mocha-nusku.kvconfig"
    grep -qx '    theme = "catppuccin-mocha-mauve-cursors",' "$XDG_CONFIG_HOME/nusku/theme/hypr-cursor.lua"
    grep -q 'gtk-cursor-theme-name=catppuccin-mocha-mauve-cursors' "$HOME/.config/gtk-3.0/settings.ini"
    grep -q 'gtk-theme-name=adw-gtk3-dark' "$HOME/.config/gtk-4.0/settings.ini"
}

@test "nusku-theme logs to one log file and hints at --update for login screen and cursor" {
    run bash scripts/nusku-theme mauve
    [ "$status" -eq 0 ]
    [ "$(find "$XDG_STATE_HOME/nusku" -maxdepth 1 -name 'install-*.log' | wc -l)" -eq 1 ]
    [[ "$output" == *"login screen"* ]]
    [[ "$output" == *"cursor"* ]]
    [[ "$output" == *"nusku-update"* ]]
}

@test "Hyprland colour and cursor modules are Lua tables from the palette" {
    run in_sub "answers_set ACCENT peach; theme_render_all '$PWD'"
    [ "$status" -eq 0 ]
    t="$XDG_CONFIG_HOME/nusku/theme"
    [ ! -e "$t/hypr-colors.conf" ]
    [ ! -e "$t/hypr-cursor.conf" ]
    grep -q '^return {' "$t/hypr-colors.lua"
    grep -qx '    accent = "rgb(fab387)",' "$t/hypr-colors.lua"
    grep -qx '    base = "rgb(1e1e2e)",' "$t/hypr-colors.lua"
    grep -qx '    surface0 = "rgb(313244)",' "$t/hypr-colors.lua"
    grep -qx '    crust = "rgb(11111b)",' "$t/hypr-colors.lua"
    [ "$(grep -c ' = "rgb(' "$t/hypr-colors.lua")" -eq 27 ]
    grep -q '^return {' "$t/hypr-cursor.lua"
    grep -qx '    theme = "catppuccin-mocha-peach-cursors",' "$t/hypr-cursor.lua"
}

@test "config/hypr has no hard-coded colours" {
    run grep -rnEi '(rgba?\(|0x)[0-9a-f]{6}|#[0-9a-f]{6}' config/hypr --include='*.lua'
    [ "$status" -ne 0 ]
}
