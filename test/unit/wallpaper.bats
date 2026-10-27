bats_require_minimum_version 1.5.0

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export XDG_STATE_HOME="$HOME/.local/state"
    export NUSKU_SDDM_BG_DIR="$BATS_TEST_TMPDIR/sddm"
    export HYPRLAND_INSTANCE_SIGNATURE=test
    mkdir -p "$HOME" "$NUSKU_SDDM_BG_DIR" "$BATS_TEST_TMPDIR/bin"
    export HCLOG="$BATS_TEST_TMPDIR/hyprctl.log"
    : >"$HCLOG"
    cat >"$BATS_TEST_TMPDIR/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HCLOG"
if [ "$1" = "monitors" ]; then
    printf '[{"name":"DP-1"},{"name":"HDMI-A-1"}]\n'
fi
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/hyprctl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    printf 'a' >"$BATS_TEST_TMPDIR/one.png"
    printf 'b' >"$BATS_TEST_TMPDIR/two.jpg"
    STATE="$HOME/.local/state/nusku"
}

@test "set all writes *= line and current-wallpaper link" {
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/one.png" all
    [ "$status" -eq 0 ]
    grep -qx "\*=$BATS_TEST_TMPDIR/one.png" "$STATE/wallpapers"
    [ "$(readlink "$STATE/current-wallpaper")" = "$BATS_TEST_TMPDIR/one.png" ]
    grep -q "hyprpaper wallpaper DP-1,$BATS_TEST_TMPDIR/one.png,cover" "$HCLOG"
    grep -q "hyprpaper wallpaper HDMI-A-1,$BATS_TEST_TMPDIR/one.png,cover" "$HCLOG"
}

@test "set one monitor keeps the * line" {
    scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/one.png" all
    : >"$HCLOG"
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/two.jpg" DP-1
    [ "$status" -eq 0 ]
    grep -qx "\*=$BATS_TEST_TMPDIR/one.png" "$STATE/wallpapers"
    grep -qx "DP-1=$BATS_TEST_TMPDIR/two.jpg" "$STATE/wallpapers"
    [ "$(grep -c 'hyprpaper wallpaper' "$HCLOG")" -eq 1 ]
    grep -q "hyprpaper wallpaper DP-1,$BATS_TEST_TMPDIR/two.jpg,cover" "$HCLOG"
}

@test "restore applies each saved line" {
    mkdir -p "$STATE"
    printf '*=%s\nDP-1=%s\n' "$BATS_TEST_TMPDIR/one.png" "$BATS_TEST_TMPDIR/two.jpg" >"$STATE/wallpapers"
    run scripts/nusku-wallpaper restore
    [ "$status" -eq 0 ]
    grep -q "hyprpaper wallpaper DP-1,$BATS_TEST_TMPDIR/two.jpg,cover" "$HCLOG"
    grep -q "hyprpaper wallpaper HDMI-A-1,$BATS_TEST_TMPDIR/one.png,cover" "$HCLOG"
    run grep -c "DP-1,$BATS_TEST_TMPDIR/one.png" "$HCLOG"
    [ "$output" = "0" ]
}

@test "restore with no state uses the default" {
    run scripts/nusku-wallpaper restore
    [ "$status" -eq 0 ]
    grep -q "hyprpaper wallpaper .*wallpapers/space.png,cover" "$HCLOG"
    grep -q 'space.png$' "$STATE/wallpapers"
}

@test "set with missing file fails with message" {
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/nope.png" all
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    [ ! -e "$STATE/wallpapers" ]
}

@test "set all copies to sddm background dir" {
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/two.jpg" all
    [ "$status" -eq 0 ]
    [ "$(cat "$NUSKU_SDDM_BG_DIR/background.jpg")" = "b" ]
    [ "$(readlink "$NUSKU_SDDM_BG_DIR/background")" = "background.jpg" ]
}

@test "set without Hyprland still writes state and does not call hyprctl" {
    unset HYPRLAND_INSTANCE_SIGNATURE
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/one.png" all
    [ "$status" -eq 0 ]
    grep -qx "\*=$BATS_TEST_TMPDIR/one.png" "$STATE/wallpapers"
    [ ! -s "$HCLOG" ]
}

@test "unwritable sddm dir warns but succeeds" {
    export NUSKU_SDDM_BG_DIR="/proc/nonexistent/sddm"
    run scripts/nusku-wallpaper set "$BATS_TEST_TMPDIR/one.png" all
    [ "$status" -eq 0 ]
    [[ "$output" == *"warning"* ]]
}

@test "list prints repo wallpapers" {
    run scripts/nusku-wallpaper list
    [ "$status" -eq 0 ]
    [[ "$output" == *"/wallpapers/space.png"* ]]
}
