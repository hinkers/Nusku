# Quick settings: lib/swaync.sh writes the panel config per machine; nusku-quick drives the toggles.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    unset NUSKU_LOG NUSKU_STEP
    export NUSKU_BACKLIGHT_DIR="$BATS_TEST_TMPDIR/backlight"
    mkdir -p "$NUSKU_BACKLIGHT_DIR"
    OUT="$BATS_TEST_TMPDIR/swaync/config.json"
}

write() {
    bash -c 'source lib/log.sh; source lib/swaync.sh; swaync_write_config config/swaync/config.template.json "$1"' _ "$OUT"
}

power_labels() { jq -r '."widget-config"."buttons-grid#power".actions[].command' "$OUT" | awk '{print $NF}' | tr '\n' ' '; }

@test "the template is valid JSON and every widget has its config" {
    jq -e . config/swaync/config.template.json >/dev/null
    run jq -r '. as $r | .widgets[] | select(. != "notifications") | select($r."widget-config"[.] == null)' \
        config/swaync/config.template.json
    [ -z "$output" ]
}

@test "laptop: brightness slider uses the machine's backlight device" {
    mkdir "$NUSKU_BACKLIGHT_DIR/amdgpu_bl1"
    NUSKU_POWER_PROFILES="power-saver balanced performance" run write
    [ "$status" -eq 0 ]
    jq -e '.widgets | index("backlight")' "$OUT" >/dev/null
    [ "$(jq -r '."widget-config".backlight.device' "$OUT")" = amdgpu_bl1 ]
    [ "$(power_labels)" = "power-saver balanced performance " ]
}

@test "desktop: no backlight, no brightness slider" {
    NUSKU_POWER_PROFILES="power-saver balanced performance" run write
    [ "$status" -eq 0 ]
    ! jq -e '.widgets | index("backlight")' "$OUT" >/dev/null
    jq -e '."widget-config".backlight == null' "$OUT" >/dev/null
}

@test "power modes the machine lacks are left out" {
    NUSKU_POWER_PROFILES="power-saver balanced" run write
    [ "$(power_labels)" = "power-saver balanced " ]
}

@test "no power profiles: the power-mode row is dropped" {
    NUSKU_POWER_PROFILES="" run write
    [ "$status" -eq 0 ]
    ! jq -e '.widgets | index("buttons-grid#power")' "$OUT" >/dev/null
}

@test "re-running gives the same file" {
    export NUSKU_POWER_PROFILES="balanced performance"
    write
    cp "$OUT" "$BATS_TEST_TMPDIR/first"
    write
    cmp "$OUT" "$BATS_TEST_TMPDIR/first"
}

@test "every toggle in the template is one nusku-quick knows" {
    run bash -c "jq -r '.. | .\"update-command\"? // empty' config/swaync/config.template.json | awk '{print \$NF}'"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    local t
    for t in $output; do
        grep -qE "^ +${t%%-*}[-*a-z]*\)" scripts/nusku-quick || { echo "unknown: $t"; false; }
    done
}

@test "nusku-quick: unknown toggle fails, power status compares the profile" {
    run scripts/nusku-quick status nope
    [ "$status" -eq 2 ]
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho balanced\n' >"$BATS_TEST_TMPDIR/bin/powerprofilesctl"
    chmod +x "$BATS_TEST_TMPDIR/bin/powerprofilesctl"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run scripts/nusku-quick status power-balanced
    [ "$output" = true ]
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run scripts/nusku-quick status power-performance
    [ "$output" = false ]
}

@test "links.txt links only the style, not the whole swaync dir" {
    grep -qx 'config/swaync/style.css .config/swaync/style.css' config/links.txt
    ! grep -qE '^config/swaync ' config/links.txt
}
