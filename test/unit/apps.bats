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
