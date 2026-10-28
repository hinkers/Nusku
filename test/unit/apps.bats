# bats' own `run` clashes with Nusku's, so Nusku code runs via bash -c.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE NUSKU_ROOT_FSTYPE
    export NUSKU_ROOT="$PWD"
    FIX="$BATS_TEST_TMPDIR/apps.list"
    cat >"$FIX" <<'LIST'
# fixture
group|g1|Group One
group|g2|Group Two
app|g1|alpha|*|Alpha|alpha alpha-extra|
app|g1|beta|-|Beta|aur:beta|multilib,gpu32
app|g2|gamma|*|Gamma|flatpak:org.gamma.App|
app|g2|snap|-|Snap|snapper|btrfs
lang|py|Python|python uv|
lang|rs|Rust|rustup|
LIST
}

# Run a snippet with log, answers and apps libs sourced (real catalogue).
in_sub() {
    bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; '"$1"
}

# Same, against the fixture catalogue.
in_fix() {
    NUSKU_APPS_LIST="$FIX" in_sub "$1"
}

@test "apps_groups lists groups in file order" {
    run in_sub 'apps_groups | tr "\n" " "'
    [ "$status" -eq 0 ]
    [ "$output" = "dev everyday media creative gaming system " ]
}

@test "apps_group_label and apps_label" {
    run in_fix 'apps_group_label g2; apps_label beta; apps_label rs'
    [ "$status" -eq 0 ]
    [ "$output" = $'Group Two\nBeta\nRust' ]
}

@test "apps_in_group lists app ids in file order" {
    run in_fix 'NUSKU_ROOT_FSTYPE=ext4; apps_in_group g1 | tr "\n" " "'
    [ "$output" = "alpha beta " ]
}

@test "apps_starred is exactly the spec's favourites" {
    run in_sub 'apps_starred'
    [ "$status" -eq 0 ]
    [ "$output" = "neovim gh claude-code firefox discord obsidian spotify vlc" ]
}

@test "apps_langs lists languages in file order" {
    run in_fix 'apps_langs | tr "\n" " "'
    [ "$output" = "py rs " ]
}

@test "apps_packages splits tokens" {
    run in_sub 'apps_packages steam'
    [ "$output" = "steam" ]
    run in_sub 'apps_packages bitwarden'
    [ "$output" = "flatpak:com.bitwarden.desktop" ]
    run in_fix 'apps_packages alpha'
    [ "$output" = $'alpha\nalpha-extra' ]
    run in_fix 'apps_packages py'
    [ "$output" = $'python\nuv' ]
}

@test "apps_has_flag" {
    run in_fix 'apps_has_flag beta multilib'
    [ "$status" -eq 0 ]
    run in_fix 'apps_has_flag beta gpu32'
    [ "$status" -eq 0 ]
    run in_fix 'apps_has_flag beta btrfs'
    [ "$status" -eq 1 ]
    run in_fix 'apps_has_flag alpha multilib'
    [ "$status" -eq 1 ]
}

@test "snapper hidden on ext4, shown on btrfs" {
    run in_sub 'NUSKU_ROOT_FSTYPE=ext4; apps_in_group system'
    [ "$status" -eq 0 ]
    [[ "$output" != *snapper* ]]
    run in_sub 'NUSKU_ROOT_FSTYPE=btrfs; apps_in_group system'
    [[ "$output" == *snapper* ]]
}

@test "apps_root_is_btrfs follows NUSKU_ROOT_FSTYPE" {
    run in_sub 'NUSKU_ROOT_FSTYPE=btrfs apps_root_is_btrfs'
    [ "$status" -eq 0 ]
    run in_sub 'NUSKU_ROOT_FSTYPE=ext4 apps_root_is_btrfs'
    [ "$status" -eq 1 ]
}

@test "apps_validate_answers rejects an unknown app" {
    run in_sub "answers_set APPS 'firefox nope'; apps_validate_answers"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown app 'nope'"* ]]
}

@test "apps_validate_answers rejects an unknown language" {
    run in_sub "answers_set LANGS 'python cobol'; apps_validate_answers"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown language 'cobol'"* ]]
}

@test "apps_validate_answers accepts known ids" {
    run in_sub "answers_set APPS 'firefox steam'; answers_set LANGS 'python rust'; apps_validate_answers"
    [ "$status" -eq 0 ]
}

@test "empty APPS and LANGS are valid" {
    run in_sub "apps_validate_answers"
    [ "$status" -eq 0 ]
    run in_sub "answers_set APPS ''; answers_set LANGS ''; apps_validate_answers"
    [ "$status" -eq 0 ]
}

@test "answers_validate checks APPS and LANGS when apps.sh is loaded" {
    run in_sub "answers_set GPU vm; answers_set AUR_HELPER paru; answers_set ACCENT mauve; answers_set APPS nope; answers_validate"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown app 'nope'"* ]]
}

@test "LANGS is a known answers key" {
    printf 'LANGS=python rust\n' >"$BATS_TEST_TMPDIR/a"
    run in_sub "answers_load '$BATS_TEST_TMPDIR/a'; answers_get LANGS"
    [ "$output" = "python rust" ]
}

@test "every app and language has a label and at least one package" {
    run in_sub '
        ids="$(awk -F"|" "\$1==\"app\"{print \$3} \$1==\"lang\"{print \$2}" "$NUSKU_APPS_LIST")"
        [ -n "$ids" ]
        for id in $ids; do
            [ -n "$(apps_label "$id")" ] || { echo "no label: $id"; exit 1; }
            [ -n "$(apps_packages "$id")" ] || { echo "no packages: $id"; exit 1; }
        done'
    [ "$status" -eq 0 ]
}

@test "no label contains a comma or pipe" {
    run in_sub '
        for id in $(apps_groups); do apps_group_label "$id"; done
        for id in $(awk -F"|" "\$1==\"app\"{print \$3} \$1==\"lang\"{print \$2}" "$NUSKU_APPS_LIST"); do apps_label "$id"; done'
    [ "$status" -eq 0 ]
    [[ "$output" != *,* ]]
    [[ "$output" != *"|"* ]]
}

@test "catalogue ids are unique across apps and languages" {
    run in_sub '
        awk -F"|" "\$1==\"app\"{print \$3} \$1==\"lang\"{print \$2}" "$NUSKU_APPS_LIST" | sort | uniq -d'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- apps_ask: the picker, driven by a fake gum -----------------------------------------
# The fake gum answers one call per reply file $GUM_DIR/replies/N (N = call number, from 1) and
# records that call's arguments to $GUM_DIR/call-N. A reply of ESC makes it exit 130 (Esc pressed).
# A multi-line reply is what a --no-limit checklist prints (one selected label per line).

fake_gum() {
    export GUM_DIR="$BATS_TEST_TMPDIR/gum"
    mkdir -p "$GUM_DIR/replies" "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gum" <<'GUM'
#!/usr/bin/env bash
n=$(( $(cat "$GUM_DIR/n" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$GUM_DIR/n"
printf '%s\n' "$@" >"$GUM_DIR/call-$n"
reply="$GUM_DIR/replies/$n"
[ -f "$reply" ] || exit 130
if [ "$(cat "$reply")" = ESC ]; then exit 130; fi
cat "$reply"
GUM
    chmod +x "$BATS_TEST_TMPDIR/bin/gum"
    local i=1 r
    for r in "$@"; do
        printf '%s\n' "$r" >"$GUM_DIR/replies/$i"
        i=$((i + 1))
    done
}

# Run apps_ask (real catalogue) after SETUP, then print APPS and LANGS.
ask() {
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
        'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; '"$1"'; apps_ask >/dev/null 2>&1; echo "APPS=$(answers_get APPS)"; echo "LANGS=$(answers_get LANGS)"'
}

@test "fresh picker defaults to the starred apps" {
    fake_gum Done
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian spotify vlc" ]
    [ "${lines[1]}" = "LANGS=" ]
}

@test "group menu shows counts and Done" {
    fake_gum Done
    run ask ':'
    [ "$status" -eq 0 ]
    grep -qxF 'Optional apps — pick a group to change, then Done' "$GUM_DIR/call-1"
    grep -qxF 'Dev (3/6)' "$GUM_DIR/call-1"
    grep -qxF 'Everyday (3/8)' "$GUM_DIR/call-1"
    grep -qxF 'Done' "$GUM_DIR/call-1"
}

@test "opening Media and unticking Spotify" {
    fake_gum 'Media (2/4)' '★ VLC' Done
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian vlc" ]
    grep -qxF 'Media — space toggles, ctrl+a selects all, enter confirms' "$GUM_DIR/call-2"
    grep -qxF -- '--no-limit' "$GUM_DIR/call-2"
    grep -qxF '★ Spotify,★ VLC' "$GUM_DIR/call-2"
}

@test "Dev opens the language picker" {
    fake_gum 'Dev (3/6)' '★ Neovim (LazyVim)' $'Python\nRust' Done
    run ask ':'
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "APPS=neovim "* ]]
    [[ "${lines[0]}" != *" gh "* && "${lines[0]}" != *claude-code* ]]
    [ "${lines[1]}" = "LANGS=python rust" ]
    grep -qxF 'Languages — runtimes, tools and Neovim support' "$GUM_DIR/call-3"
}

@test "Esc in a group keeps its selection" {
    fake_gum 'Media (2/4)' ESC Done
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian spotify vlc" ]
}

@test "re-asking starts from saved picks" {
    fake_gum Done
    run ask "answers_set APPS gimp; answers_set LANGS go"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=gimp" ]
    [ "${lines[1]}" = "LANGS=go" ]
    grep -qxF 'Creative (1/5)' "$GUM_DIR/call-1"
    grep -qxF 'Dev (0/6)' "$GUM_DIR/call-1"
}

@test "snapper not offered on ext4" {
    export NUSKU_ROOT_FSTYPE=ext4
    fake_gum 'System tools (0/4)' ESC Done
    run ask ':'
    [ "$status" -eq 0 ]
    grep -qxF 'System tools (0/4)' "$GUM_DIR/call-1"
    run grep -c 'Snapper' "$GUM_DIR/call-2"
    [ "$output" = 0 ]
    grep -qF 'GParted' "$GUM_DIR/call-2"
}

@test "snapper offered on btrfs" {
    export NUSKU_ROOT_FSTYPE=btrfs
    fake_gum 'System tools (0/5)' ESC Done
    run ask ':'
    [ "$status" -eq 0 ]
    grep -qF 'Snapper' "$GUM_DIR/call-2"
}

@test "non-interactive without APPS installs no optional apps" {
    run in_sub 'export NUSKU_NONINTERACTIVE=1; apps_default_missing; echo "APPS=[$(answers_get APPS)] LANGS=[$(answers_get LANGS)]"; [ -n "${NUSKU_ANSWERS[APPS]+x}" ] && echo stored'
    [ "$status" -eq 0 ]
    [[ "$output" == *"No optional apps selected (add some with ./install.sh --apps)"* ]]
    [[ "$output" == *"APPS=[] LANGS=[]"* ]]
    [[ "$output" == *stored* ]]
}

@test "non-interactive with APPS saved keeps it and stays quiet" {
    run in_sub 'export NUSKU_NONINTERACTIVE=1; answers_set APPS gimp; apps_default_missing; echo "APPS=[$(answers_get APPS)] LANGS=[$(answers_get LANGS)]"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"No optional apps"* ]]
    [[ "$output" == *"APPS=[gimp] LANGS=[]"* ]]
}

@test "ticking None clears the group" {
    fake_gum 'Media (2/4)' $'None\n★ VLC' Done
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian" ]
    grep -qxF None "$GUM_DIR/call-2"
}

@test "ticking None clears the languages" {
    fake_gum 'Dev (3/6)' ESC None Done
    run ask 'answers_set LANGS "python rust"'
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "LANGS=" ]
}

@test "empty confirm clears the group" {
    fake_gum 'Media (2/4)' '' Done
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian" ]
}
