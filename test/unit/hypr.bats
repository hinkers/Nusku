setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" HOME="$BATS_TEST_TMPDIR/home"
    unset NUSKU_LOG NUSKU_STEP
    D="$BATS_TEST_TMPDIR/nusku"
    mkdir -p "$D/theme"
}

in_sub() {
    bash -c 'source lib/log.sh; source lib/hypr.sh; '"$1"
}

@test "hypr_write_local_lua creates a commented Lua file once" {
    run in_sub "hypr_write_local_lua '$D/local.lua'"
    [ "$status" -eq 0 ]
    [ -s "$D/local.lua" ]
    # Only Lua comments: nothing that would change the config by default.
    [ -z "$(grep -v '^--' "$D/local.lua")" ]
    grep -q 'hl.monitor' "$D/local.lua"
    printf 'hl.config({ general = { gaps_in = 1 } })\n' >"$D/local.lua"
    run in_sub "hypr_write_local_lua '$D/local.lua'"
    [ "$status" -eq 0 ]
    [ "$(cat "$D/local.lua")" = 'hl.config({ general = { gaps_in = 1 } })' ]
}

@test "hypr_migrate_legacy removes the generated hyprlang files" {
    : >"$D/gpu.conf"
    : >"$D/theme/hypr-colors.conf"
    : >"$D/theme/hypr-cursor.conf"
    : >"$D/theme/hyprlock-colors.conf"
    run in_sub "hypr_migrate_legacy '$D'"
    [ "$status" -eq 0 ]
    [ ! -e "$D/gpu.conf" ]
    [ ! -e "$D/theme/hypr-colors.conf" ]
    [ ! -e "$D/theme/hypr-cursor.conf" ]
    # hyprlock still reads hyprlang.
    [ -e "$D/theme/hyprlock-colors.conf" ]
}

@test "hypr_migrate_legacy keeps a local.conf with overrides and warns once" {
    printf '# mine\nmonitor = DP-1, 2560x1440@144, 0x0, 1\n\nbind = SUPER, B, exec, firefox\n' >"$D/local.conf"
    run in_sub "hypr_migrate_legacy '$D'"
    [ "$status" -eq 0 ]
    [ -f "$D/local.conf" ]
    grep -q 'DP-1' "$D/local.conf"
    [ "$(grep -c 'WARN' <<<"$output")" -eq 1 ]
    [[ "$output" == *"$D/local.conf"* ]]
    [[ "$output" == *"local.lua"* ]]
}

@test "hypr_migrate_legacy is quiet about a comments-only local.conf" {
    printf '# Your own Hyprland settings.\n#   monitor = DP-1, 2560x1440@144, 0x0, 1\n\n   \n' >"$D/local.conf"
    run in_sub "hypr_migrate_legacy '$D'"
    [ "$status" -eq 0 ]
    [[ "$output" != *WARN* ]]
    [ -f "$D/local.conf" ]
}

@test "hypr_migrate_legacy on a fresh install does nothing" {
    run in_sub "hypr_migrate_legacy '$D'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Hyprland reads Lua: hyprland.lua exists and no hyprlang Hyprland config is left" {
    [ -f config/hypr/hyprland.lua ]
    for f in hyprland env monitors input looks animations keybinds rules autostart; do
        [ ! -e "config/hypr/$f.conf" ]
    done
    [ ! -e theme/templates/hypr-colors.conf.tmpl ]
    [ ! -e theme/templates/hypr-cursor.conf.tmpl ]
}

@test "no legacy 'hyprctl dispatch <name>' calls (Lua configs need hl.dsp expressions)" {
    run grep -rnE "hyprctl dispatch +[a-z]" config scripts test/hyperv
    [ "$status" -ne 0 ]
}
