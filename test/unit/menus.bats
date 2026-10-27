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
