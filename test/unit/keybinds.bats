# Keybinds go through bindlib, which describes each bind and writes the keybind manifest.

setup() {
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    export MANIFEST="$XDG_RUNTIME_DIR/nusku/keybinds.tsv"
    unset HYPR_STUB_EXISTS HYPR_STUB_MISSING HYPR_STUB_LOADS
    export HYPR_STUB_REPORT=binds
}

load_binds() {
    run nvim --headless -l test/fixtures/hypr-stub.lua "${1:-config/hypr/keybinds.lua}"
    [ "$status" -eq 0 ]
}

# run awk PROGRAM over the manifest (tab-separated)
records() {
    awk -F'\t' "$1" "$MANIFEST"
}

@test "every bind has a description" {
    load_binds
    [ "$(records '$1 == "bind"' | wc -l)" -gt 0 ]
    [ "$(records '$1 == "bind" && $4 == ""' | wc -l)" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq "$(records '$1 == "bind"' | wc -l)" ]
    # the description is also passed to hl.bind
    ! awk -F'\t' '$2 == "nil" || $2 == ""' <<<"$output" | grep -q . || false
    [ "$(records '{ print NF }' | sort -u)" = "6" ]
}

@test "no raw hl.bind outside bindlib" {
    ! grep -n 'hl.bind(' config/hypr/keybinds.lua || false
}

@test "manifest is rewritten on reload" {
    load_binds
    once="$(wc -l <"$MANIFEST")"
    HYPR_STUB_LOADS=2 load_binds
    [ "$(wc -l <"$MANIFEST")" -eq "$once" ]
}

@test "screenshot binds are listed and runnable" {
    load_binds
    [ "$(records '$1 == "bind" && $4 ~ /Screenshot/' | wc -l)" -eq 3 ]
    [ "$(records '$4 ~ /Screenshot/ { print $5 }' | sort -u)" = "1" ]
    [ "$(records '$4 ~ /Screenshot/ { print $3 }' | sort)" = "CTRL + Print
Print
SHIFT + Print" ]
    records '$3 == "Print" { print $4 "|" $6 }' | grep -qxF 'Screenshot a region|hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots")'
}

@test "mouse binds and held resizes are list-only, volume is runnable" {
    load_binds
    [ "$(records '$3 == "SUPER + mouse:273" { print $5 }')" = "0" ]
    [ "$(records '$3 ~ /mouse_(up|down)/ { print $5 }' | sort -u)" = "0" ]
    [ "$(records '$3 ~ /CTRL [+] (left|right|up|down)$/ { print $5 }' | sort -u)" = "0" ]
    [ "$(records '$4 ~ /olume/ { print $5 }' | sort -u)" = "1" ]
    [ "$(records '$3 == "SUPER + mouse:272" { print $5 }')" = "0" ]
    [ "$(records '$3 == "SUPER + CTRL + left" { print $5 }')" = "0" ]
    [ "$(records '$3 == "SUPER + Q" { print $5 }')" = "1" ]
}

@test "workspace binds collapse into groups" {
    load_binds
    [ "$(records '$1 == "group" && $2 == "ws-go" { print $3 "|" $4 "|" $6 }')" = "SUPER + 1…0|Go to workspace 1–10|Workspace" ]
    [ "$(records '$1 == "group" && $2 == "ws-move" { print $3 "|" $4 "|" $6 }')" = "SUPER + SHIFT + 1…0|Move window to workspace 1–10|Workspace" ]
    [ "$(records '$1 == "bind" && $2 == "ws-go"' | wc -l)" -eq 10 ]
    [ "$(records '$1 == "bind" && $2 == "ws-move"' | wc -l)" -eq 10 ]
    [ "$(records '$2 == "ws-go" && $3 == "SUPER + 0" { print $4 "|" $6 }')" = '10|hl.dsp.focus({ workspace = 10 })' ]
    [ "$(records '$2 == "ws-move" && $3 == "SUPER + SHIFT + 1" { print $4 "|" $6 }')" = '1|hl.dsp.window.move({ workspace = 1 })' ]
}

@test "keybind menu bind is SUPER + slash" {
    load_binds
    [ "$(records '$3 == "SUPER + slash" { print $4 "|" $5 "|" $6 }')" = 'Search keybinds|1|hl.dsp.exec_cmd("~/.local/bin/nusku-menu-keybinds")' ]
}

@test "Yazi bind only when yazi exists" {
    HYPR_STUB_EXISTS=/usr/bin/yazi load_binds
    records '$3 == "SUPER + SHIFT + E" { print $6 }' | grep -qxF 'hl.dsp.exec_cmd("kitty -e yazi")'
    HYPR_STUB_MISSING=/usr/bin/yazi load_binds
    ! records '$3 == "SUPER + SHIFT + E"' | grep -q . || false
    ! grep -q 'SUPER + SHIFT + E' <<<"$output" || false
}

@test "Firefox bind only when firefox exists" {
    HYPR_STUB_EXISTS=/usr/bin/firefox load_binds
    records '$3 == "SUPER + B" { print $6 }' | grep -qxF 'hl.dsp.exec_cmd("firefox")'
    HYPR_STUB_MISSING=/usr/bin/firefox load_binds
    ! records '$3 == "SUPER + B"' | grep -q . || false
}

@test "fields with tabs are sanitised" {
    cat >"$BATS_TEST_TMPDIR/one.lua" <<'LUA'
local B = require("bindlib")
B.reset()
B.bind("X", "a\tb\nc", 'hl.dsp.exec_cmd("x")')
LUA
    load_binds "$BATS_TEST_TMPDIR/one.lua"
    [ "$(cat "$MANIFEST")" = "$(printf 'bind\t\tX\ta b c\t1\thl.dsp.exec_cmd("x")')" ]
}

@test "an empty description is an error" {
    cat >"$BATS_TEST_TMPDIR/bad.lua" <<'LUA'
local B = require("bindlib")
B.reset()
B.bind("X", "", 'hl.dsp.exec_cmd("x")')
LUA
    run nvim --headless -l test/fixtures/hypr-stub.lua "$BATS_TEST_TMPDIR/bad.lua"
    [ "$status" -ne 0 ]
    [[ "$output" == *"description"* ]]
}

@test "group is not passed to hl.bind" {
    cat >"$BATS_TEST_TMPDIR/grp.lua" <<'LUA'
local B = require("bindlib")
B.reset()
B.bind("X", "1", 'hl.dsp.exec_cmd("x")', { group = "g", locked = true })
LUA
    load_binds "$BATS_TEST_TMPDIR/grp.lua"
    [ "$(records '{ print $2 }')" = "g" ]
    [ "$output" = "$(printf 'X\t1\tdescription,locked')" ]
}

@test "binds from a local module appear in the manifest after keybinds" {
    cat >"$BATS_TEST_TMPDIR/both.lua" <<'LUA'
dofile("config/hypr/keybinds.lua")
local B = require("bindlib")
B.bind("SUPER + D", "Discord", 'hl.dsp.exec_cmd("discord")')
LUA
    load_binds "$BATS_TEST_TMPDIR/both.lua"
    records '$3 == "SUPER + D" { print $4 "|" $5 "|" $6 }' | grep -qxF 'Discord|1|hl.dsp.exec_cmd("discord")'
    records '$3 == "SUPER + slash"' | grep -q .
}
