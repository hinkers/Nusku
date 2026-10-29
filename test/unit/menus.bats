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
