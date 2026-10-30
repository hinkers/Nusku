# rofi menu scripts, with a stub rofi that records its arguments.

setup() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export ROFI_ARGS="$BATS_TEST_TMPDIR/rofi-args"
    : >"$ROFI_ARGS"
    cat >"$BATS_TEST_TMPDIR/bin/rofi" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ROFI_ARGS"
cat >/dev/null
printf '%s\n' "${ROFI_PICK:-}"
[ -n "${ROFI_PICK:-}" ]
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/rofi"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "nusku-menu-power sizes the list with -theme-str, not the removed -lines option" {
    run scripts/nusku-menu-power
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '-lines' "$ROFI_ARGS")" -eq 0 ]
    grep -qF 'listview { lines: 5; }' "$ROFI_ARGS"
}

@test "nusku-menu-power confirm dialog uses two lines" {
    export ROFI_PICK=Reboot
    run scripts/nusku-menu-power
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '-lines' "$ROFI_ARGS")" -eq 0 ]
    grep -qF 'listview { lines: 2; }' "$ROFI_ARGS"
}

# --- nusku-menu-keybinds ---------------------------------------------------

kb_setup() {
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
    mkdir -p "$XDG_RUNTIME_DIR/nusku"
    {
        printf 'bind\t\tPrint\tScreenshot a region\t1\thl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots")\n'
        printf 'bind\t\tSUPER + mouse:272\tDrag to move window\t0\thl.dsp.window.drag()\n'
        for i in 1 2 3; do
            printf 'bind\tws-go\tSUPER + %s\t%s\t1\thl.dsp.focus({ workspace = %s })\n' "$i" "$i" "$i"
        done
        printf 'group\tws-go\tSUPER + 1…0\tGo to workspace\t1\tWorkspace\n'
        printf 'bind\t\tSUPER + Q\tClose window\t1\thl.dsp.window.close()\n'
        printf 'bind\t\tSUPER + slash\tSearch keybinds\t1\thl.dsp.exec_cmd("x")\n'
        printf 'bind\t\tXF86AudioMute\tMute\t1\thl.dsp.exec_cmd("m")\n'
    } >"$XDG_RUNTIME_DIR/nusku/keybinds.tsv"
    export HYPR_ARGS="$BATS_TEST_TMPDIR/hypr-args"
    : >"$HYPR_ARGS"
    printf '#!/usr/bin/env bash\necho "$*" >>"$HYPR_ARGS"\n' >"$BATS_TEST_TMPDIR/bin/hyprctl"
    printf '#!/usr/bin/env bash\necho "$*" >>"$NOTIFY_ARGS"\n' >"$BATS_TEST_TMPDIR/bin/notify-send"
    export NOTIFY_ARGS="$BATS_TEST_TMPDIR/notify-args"
    chmod +x "$BATS_TEST_TMPDIR/bin/hyprctl" "$BATS_TEST_TMPDIR/bin/notify-send"
    # rofi stub: -format i picks by index; the pick queue file holds one pick per rofi call
    cat >"$BATS_TEST_TMPDIR/bin/rofi" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ROFI_ARGS"
cat >>"$ROFI_ARGS.stdin"
q="$ROFI_ARGS.queue"
[ -s "$q" ] || exit 1
read -r first rest <"$q"
echo "$rest" >"$q"
echo "$first"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/rofi"
}

kb_picks() { echo "$*" >"$ROFI_ARGS.queue"; }

@test "keybind menu lists description and keys" {
    kb_setup
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    grep -E 'Screenshot a region +Print' "$ROFI_ARGS.stdin"
    grep -E 'Search keybinds +SUPER \+ /$' "$ROFI_ARGS.stdin"
    grep -E 'Drag to move window +SUPER \+ Left drag$' "$ROFI_ARGS.stdin"
    grep -E 'Mute +Mute key$' "$ROFI_ARGS.stdin"
    grep -qE 'Close window {4,}SUPER [+] Q' "$ROFI_ARGS.stdin"
    grep -qF -- '-p Keybinds' "$ROFI_ARGS"
    grep -qF -- '-format i' "$ROFI_ARGS"
}

@test "keybind menu runs the picked bind" {
    kb_setup; kb_picks 0
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    [ "$(cat "$HYPR_ARGS")" = 'dispatch hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots")' ]
}

@test "keybind menu does not run a mouse bind" {
    kb_setup; kb_picks 1
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    [ ! -s "$HYPR_ARGS" ]
}

@test "keybind menu collapses workspace binds" {
    kb_setup; kb_picks "2 2"
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    [ "$(grep -c 'Go to workspace' "$ROFI_ARGS.stdin")" -eq 1 ]
    [ "$(wc -l <"$ROFI_ARGS.stdin")" -ge 4 ]
    [ "$(cat "$HYPR_ARGS")" = 'dispatch hl.dsp.focus({ workspace = 3 })' ]
    grep -qF -- '-p Workspace' "$ROFI_ARGS"
}

@test "keybind menu Esc runs nothing" {
    kb_setup
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    [ ! -s "$HYPR_ARGS" ]
}

@test "keybind menu without a manifest says so" {
    kb_setup
    rm "$XDG_RUNTIME_DIR/nusku/keybinds.tsv"
    run scripts/nusku-menu-keybinds
    [ "$status" -eq 0 ]
    grep -qF 'Keybind list not ready; reload Hyprland' "$NOTIFY_ARGS"
}

# --- nusku-menu-wifi / nusku-menu-bluetooth --------------------------------

net_setup() {
    kb_setup
    export CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    # nmcli stub: Wi-Fi on; two APs for "Home" (keep the stronger), an open café, a saved "Work".
    cat >"$BATS_TEST_TMPDIR/bin/nmcli" <<'STUB'
#!/usr/bin/env bash
echo "nmcli $*" >>"$CALLS"
case "$*" in
    "radio wifi") echo enabled ;;
    *"dev wifi list"*)
        printf ' :Home:40:WPA2\n*:Home:70:WPA2\n :Cafe\\: Free:55:\n :Work:30:WPA2\n' ;;
    "-t -f NAME,TYPE con show") printf 'Work:802-11-wireless\nWired:802-3-ethernet\n' ;;
    "dev wifi connect"*) exit "${CONNECT_RC:-0}" ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/nmcli"
}

@test "wifi menu: strongest first, one row per network, the connected one marked" {
    net_setup
    run scripts/nusku-menu-wifi
    [ "$(sed -n 1p "$ROFI_ARGS.stdin")" = "󰤥  Home  󰌾" ]
    [ "$(sed -n 2p "$ROFI_ARGS.stdin")" = "󰤥  Cafe: Free" ]
    [ "$(grep -c Home "$ROFI_ARGS.stdin")" -eq 1 ]
    grep -qF -- '-format i -a 0' "$ROFI_ARGS"
}

@test "wifi menu: a saved network connects with its stored password" {
    net_setup
    kb_picks 2
    run scripts/nusku-menu-wifi
    grep -qx 'nmcli con up id Work' "$CALLS"
    ! grep -q 'dev wifi connect' "$CALLS" || false
}

@test "wifi menu: a new secured network asks for the password" {
    net_setup
    kb_picks 0 hunter2
    # Pick "Home" while not connected to it: drop the active marker from the stub.
    sed -i 's/\*:Home:70/ :Home:70/' "$BATS_TEST_TMPDIR/bin/nmcli"
    run scripts/nusku-menu-wifi
    grep -qF -- '-password' "$ROFI_ARGS"
    grep -qx 'nmcli dev wifi connect Home password hunter2' "$CALLS"
}

@test "wifi menu: a failed connect removes the half-made profile" {
    net_setup
    kb_picks 1
    CONNECT_RC=1 run scripts/nusku-menu-wifi
    grep -qx 'nmcli dev wifi connect Cafe: Free' "$CALLS"
    grep -qx 'nmcli con delete id Cafe: Free' "$CALLS"
}

bt_setup() {
    kb_setup
    export CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    cat >"$BATS_TEST_TMPDIR/bin/bluetoothctl" <<'STUB'
#!/usr/bin/env bash
echo "bluetoothctl $*" >>"$CALLS"
case "$*" in
    show) echo "	Powered: yes" ;;
    "devices Paired") printf 'Device AA:AA:AA:AA:AA:01 Buds\nDevice AA:AA:AA:AA:AA:02 Mouse\n' ;;
    devices) printf 'Device AA:AA:AA:AA:AA:01 Buds\nDevice AA:AA:AA:AA:AA:02 Mouse\nDevice BB:BB:BB:BB:BB:03 Speaker\nDevice CC:CC:CC:CC:CC:04 CC-CC-CC-CC-CC-04\n' ;;
    "info AA:AA:AA:AA:AA:01") printf '\tName: Buds\n\tIcon: audio-headset\n\tConnected: no\n' ;;
    "info AA:AA:AA:AA:AA:02") printf '\tName: Mouse\n\tIcon: input-mouse\n\tConnected: yes\n' ;;
    "info BB:BB:BB:BB:BB:03") printf '\tName: Speaker\n\tIcon: audio-card\n\tConnected: no\n' ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/bluetoothctl"
}

@test "bluetooth menu: connected first, then paired, then new; unnamed devices hidden" {
    bt_setup
    run scripts/nusku-menu-bluetooth
    [ "$(sed -n 1p "$ROFI_ARGS.stdin")" = "󰍽  Mouse  ·  connected" ]
    [ "$(sed -n 2p "$ROFI_ARGS.stdin")" = "󰋋  Buds" ]
    [ "$(sed -n 3p "$ROFI_ARGS.stdin")" = "󰓃  Speaker  ·  pair" ]
    ! grep -q 'CC-CC' "$ROFI_ARGS.stdin" || false
    grep -qF -- '-format i -a 0' "$ROFI_ARGS"
}

@test "bluetooth menu: connect, disconnect and pair do the right thing" {
    bt_setup
    kb_picks 1
    run scripts/nusku-menu-bluetooth
    grep -qx 'bluetoothctl connect AA:AA:AA:AA:AA:01' "$CALLS"
    kb_picks 0
    run scripts/nusku-menu-bluetooth
    grep -qx 'bluetoothctl disconnect AA:AA:AA:AA:AA:02' "$CALLS"
    kb_picks 2
    run scripts/nusku-menu-bluetooth
    grep -qx 'bluetoothctl pair BB:BB:BB:BB:BB:03' "$CALLS"
    grep -qx 'bluetoothctl trust BB:BB:BB:BB:BB:03' "$CALLS"
}
