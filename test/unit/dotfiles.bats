bats_require_minimum_version 1.5.0

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE NUSKU_RUN_ID
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/config"
    echo new >"$REPO/config/a.conf"
    mkdir -p "$REPO/config/dir"
    echo d >"$REPO/config/dir/f"
    load_libs='source lib/log.sh; source lib/backup.sh; source lib/dotfiles.sh; '
}

in_sub() { bash -c "$load_libs"'set -e; '"$1"; }

@test "links a new file" {
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/.config/a.conf'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.config/a.conf")" = "$REPO/config/a.conf" ]
}

@test "backs up an existing regular file" {
    echo old >"$HOME/a.conf"
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/a.conf'"
    [ "$status" -eq 0 ]
    [ -L "$HOME/a.conf" ]
    [ "$(cat "$XDG_STATE_HOME"/nusku/backup-*/a.conf)" = old ]
}

@test "backs up an existing directory" {
    mkdir -p "$HOME/.config/dir"
    echo old >"$HOME/.config/dir/x"
    run in_sub "link_file '$REPO/config/dir' '$HOME/.config/dir'"
    [ "$status" -eq 0 ]
    [ -L "$HOME/.config/dir" ]
    [ "$(cat "$XDG_STATE_HOME"/nusku/backup-*/.config/dir/x)" = old ]
}

@test "existing correct link is a no-op and creates no backup dir" {
    ln -s "$REPO/config/a.conf" "$HOME/a.conf"
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/a.conf'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/a.conf")" = "$REPO/config/a.conf" ]
    [ ! -e "$XDG_STATE_HOME/nusku" ] || [ -z "$(ls "$XDG_STATE_HOME"/nusku | grep '^backup-')" ]
}

@test "link from an old repo path is replaced without backup" {
    ln -s "/old/place/Nusku/config/a.conf" "$HOME/a.conf"
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/a.conf'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/a.conf")" = "$REPO/config/a.conf" ]
    [ ! -e "$XDG_STATE_HOME/nusku" ] || [ -z "$(ls "$XDG_STATE_HOME"/nusku | grep '^backup-')" ]
}

@test "foreign symlink is backed up" {
    ln -s /somewhere/else "$HOME/a.conf"
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/a.conf'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/a.conf")" = "$REPO/config/a.conf" ]
    b="$(echo "$XDG_STATE_HOME"/nusku/backup-*/a.conf)"
    [ -L "$b" ]
    [ "$(readlink "$b")" = /somewhere/else ]
}

@test "creates missing parent dirs" {
    run in_sub "link_file '$REPO/config/a.conf' '$HOME/x/y/z/a.conf'"
    [ "$status" -eq 0 ]
    [ -L "$HOME/x/y/z/a.conf" ]
}

@test "manifest comments ignored" {
    printf '# comment\n\nconfig/a.conf .a.conf\n   # indented\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -eq 0 ]
    [ -L "$HOME/.a.conf" ]
    [ "$(find "$HOME" -type l | wc -l)" -eq 1 ]
}

@test "missing source is warned and skipped" {
    printf 'config/nope .config/nope\nconfig/a.conf .a.conf\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [ ! -e "$HOME/.config/nope" ]
    [ -L "$HOME/.a.conf" ]
}

@test "glob source links each match into dest dir" {
    mkdir -p "$REPO/scripts"
    echo 1 >"$REPO/scripts/nusku-one"
    echo 2 >"$REPO/scripts/nusku-two"
    printf 'scripts/nusku-* .local/bin\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.local/bin/nusku-one")" = "$REPO/scripts/nusku-one" ]
    [ -L "$HOME/.local/bin/nusku-two" ]
}

@test "glob with no matches is skipped silently" {
    printf 'scripts/nusku-* .local/bin\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "absolute and parent-relative dests are rejected" {
    printf 'config/a.conf /etc/a.conf\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -ne 0 ]
    printf 'config/a.conf ../a.conf\n' >"$REPO/links.txt"
    run in_sub "deploy_dotfiles '$REPO' '$REPO/links.txt'"
    [ "$status" -ne 0 ]
}
