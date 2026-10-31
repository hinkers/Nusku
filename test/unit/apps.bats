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
    [ "$output" = "dev everyday media creative artcraft gaming system " ]
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

# --- apps_ask: the folding app list, driven by keys from a file ----------------------------
# Keys go through NUSKU_TUI_IN; the screen goes to $BATS_TEST_TMPDIR/screen. Running out of keys
# acts like Esc. Rows start folded: Dev, Languages, Everyday, Media, Creative, ArtCraft, Gaming,
# System tools, then Done. Key names: U D L R (arrows), E (End), S (space), N (enter), X (Esc).

keys() {
    local k out=""
    for k in "$@"; do
        case "$k" in
            U) out+=$'\e[A' ;; D) out+=$'\e[B' ;; R) out+=$'\e[C' ;; L) out+=$'\e[D' ;;
            E) out+=$'\e[F' ;; S) out+=' ' ;; N) out+=$'\n' ;; X) out+=$'\e' ;; C) out+=$'\x03' ;;
        esac
    done
    printf '%s' "$out" >"$BATS_TEST_TMPDIR/keys"
}

# Run apps_ask (real catalogue) after SETUP, then print APPS and LANGS. Its stderr goes to
# $BATS_TEST_TMPDIR/ask.err.
ask() {
    ASK_ERR="$BATS_TEST_TMPDIR/ask.err" NUSKU_TUI_IN="$BATS_TEST_TMPDIR/keys" \
        NUSKU_TUI_OUT="$BATS_TEST_TMPDIR/screen" bash -c \
        'source lib/log.sh; source lib/answers.sh; source lib/tui.sh; source lib/apps.sh; '"$1"'; apps_ask >/dev/null 2>"$ASK_ERR"; echo "APPS=$(answers_get APPS)"; echo "LANGS=$(answers_get LANGS)"'
}

# screen: the last frame drawn, without colour codes.
screen() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$BATS_TEST_TMPDIR/screen"; }

@test "fresh picker defaults to the starred apps" {
    keys E N
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian spotify vlc" ]
    [ "${lines[1]}" = "LANGS=" ]
}

@test "groups are folded with counts; Languages sits under Dev" {
    keys E N
    run ask ':'
    screen | grep -qE 'Dev +3/6'
    screen | grep -qE 'Languages +0/10'
    screen | grep -qE 'Everyday +3/13'
    screen | grep -qE ' Done$'
    [ "$(screen | grep -n 'Languages' | tail -1 | cut -d: -f1)" -eq "$(( $(screen | grep -n 'Dev ' | tail -1 | cut -d: -f1) + 1 ))" ]
    ! screen | grep -q 'Neovim' || false
}

@test "Enter unfolds a group; Space unticks one app" {
    # Media is the 4th row: open it, move to Spotify (first item), untick, Done.
    keys D D D N D S E N
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian vlc" ]
}

@test "Space on a group ticks all of it, then clears it" {
    keys D D D S E N
    run ask ':'
    [[ "${lines[0]}" == *" spotify vlc obs audacity" ]]
    keys D D D S S E N
    run ask ':'
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian" ]
}

@test "languages are ticked in the same list" {
    # Languages is the 2nd row: open it, tick Python (1st) and PHP (2nd).
    keys D R D S D S E N
    run ask ':'
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "LANGS=python php" ]
}

@test "Left on an app folds its group and moves to it" {
    keys D D D N D L S E N
    run ask ':'
    # Left landed on Media (folded); Space then ticked the whole group.
    [[ "${lines[0]}" == *" spotify vlc obs audacity" ]]
}

@test "Esc leaves without changes" {
    keys D D D N D S X
    run ask 'answers_set APPS "gimp spotify"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=spotify gimp" ]
}

@test "Esc on a fresh run keeps the starred apps" {
    keys X
    run ask ':'
    [ "${lines[0]}" = "APPS=neovim gh claude-code firefox discord obsidian spotify vlc" ]
}

@test "Ctrl+C cancels the install" {
    keys D D D N C
    run ask ':'
    [ "$status" -eq 1 ]
    grep -qx Cancelled "$BATS_TEST_TMPDIR/ask.err"
    [[ "$output" != *APPS=* ]]
}

@test "re-asking starts from saved picks" {
    keys E N
    run ask "answers_set APPS gimp; answers_set LANGS go"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "APPS=gimp" ]
    [ "${lines[1]}" = "LANGS=go" ]
    screen | grep -qE 'Creative +1/5'
    screen | grep -qE 'Dev +0/6'
    screen | grep -qE 'Languages +1/10'
}

@test "snapper not offered on ext4" {
    export NUSKU_ROOT_FSTYPE=ext4
    keys E U R E N
    run ask ':'
    screen | grep -qE 'System tools +0/7'
    ! screen | grep -q Snapper || false
    screen | grep -q GParted
}

@test "snapper offered on btrfs" {
    export NUSKU_ROOT_FSTYPE=btrfs
    keys E U R E N
    run ask ':'
    screen | grep -qE 'System tools +0/8'
    screen | grep -q Snapper
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

# --- Installing the picks -------------------------------------------------------------

@test "apps_gpu32 amd" {
    run in_sub 'apps_gpu32 amd open'
    [ "$status" -eq 0 ]
    [ "$output" = "lib32-mesa lib32-vulkan-radeon" ]
}

@test "apps_gpu32 intel" {
    run in_sub 'apps_gpu32 intel open'
    [ "$output" = "lib32-mesa lib32-vulkan-intel" ]
}

@test "apps_gpu32 nvidia open" {
    run in_sub 'apps_gpu32 nvidia open'
    [ "$output" = "lib32-nvidia-utils" ]
}

@test "apps_gpu32 nvidia proprietary" {
    run in_sub 'apps_gpu32 nvidia proprietary'
    [ "$output" = "aur:lib32-nvidia-580xx-utils" ]
}

@test "apps_gpu32 hybrid-intel open" {
    run in_sub 'apps_gpu32 hybrid-intel open'
    [ "$output" = "lib32-mesa lib32-vulkan-intel lib32-nvidia-utils" ]
}

@test "apps_gpu32 hybrid-intel proprietary" {
    run in_sub 'apps_gpu32 hybrid-intel proprietary'
    [ "$output" = "lib32-mesa lib32-vulkan-intel aur:lib32-nvidia-580xx-utils" ]
}

@test "apps_gpu32 hybrid-amd open" {
    run in_sub 'apps_gpu32 hybrid-amd open'
    [ "$output" = "lib32-mesa lib32-vulkan-radeon lib32-nvidia-utils" ]
}

@test "apps_gpu32 vm" {
    run in_sub 'apps_gpu32 vm open'
    [ "$output" = "lib32-mesa lib32-vulkan-swrast" ]
}

@test "steam on legacy nvidia goes through the AUR helper together with the driver" {
    run in_sub 'answers_set APPS steam; apps_batches nvidia proprietary'
    [ "$status" -eq 0 ]
    [[ "$output" == *"aur steam lib32-nvidia-580xx-utils"* ]]
    [[ "$output" == *"aur steam steam"* ]]
    [[ "$output" != *"repo steam"* ]]
    [[ "$output" != *"lib32-nvidia-utils"* ]]
}

@test "steam on amd stays in the repo batch" {
    run in_sub 'answers_set APPS steam; apps_batches amd open'
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo steam"* ]]
    [[ "$output" == *"repo lib32-vulkan-radeon"* ]]
    [[ "$output" != *"aur "* ]]
}

@test "bitwarden adds flatpak to the repo batch" {
    run in_sub 'answers_set APPS bitwarden; apps_batches amd open'
    [[ "$output" == *"flatpak bitwarden com.bitwarden.desktop"* ]]
    [[ "$output" == *"repo flatpak"* ]]
}

@test "languages contribute packages" {
    run in_sub 'answers_set LANGS python; apps_batches amd open'
    [[ "$output" == *"repo python"* ]]
    [[ "$output" == *"repo uv"* ]]
}

@test "aur apps are batched under their own id" {
    run in_sub 'answers_set APPS "heroic"; apps_batches amd open'
    [ "$output" = "aur heroic heroic-games-launcher-bin" ]
}

@test "apps_batches skips btrfs apps on a non-btrfs root and says so" {
    NUSKU_ROOT_FSTYPE=ext4 run in_sub 'answers_set APPS "snapper gparted"; apps_batches amd open 2>&1'
    [[ "$output" == *"Skipping Snapper: / is not btrfs"* ]]
    [[ "$output" == *"repo gparted"* ]]
    [[ "$output" != *"repo snapper"* ]]
}

@test "apps_batches keeps btrfs apps on a btrfs root" {
    NUSKU_ROOT_FSTYPE=btrfs run in_sub 'answers_set APPS snapper; apps_batches amd open'
    [[ "$output" == *"repo snapper"* ]]
}

@test "apps_needs_multilib is true for multilib and gpu32 apps only" {
    run in_sub 'answers_set APPS "gimp mangohud"; apps_needs_multilib'
    [ "$status" -eq 0 ]
    run in_sub 'answers_set APPS "gimp steam"; apps_needs_multilib'
    [ "$status" -eq 0 ]
    run in_sub 'answers_set APPS "gimp vlc"; apps_needs_multilib'
    [ "$status" -ne 0 ]
    run in_sub 'answers_set APPS ""; apps_needs_multilib'
    [ "$status" -ne 0 ]
}

@test "summary lists failed apps" {
    run in_sub 'NUSKU_APP_FAILURES=("Heroic Games Launcher: AUR install failed" "Bitwarden: flatpak install failed"); apps_summary_failures'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not installed (see the log)"* ]]
    [[ "$output" == *"Heroic Games Launcher: AUR install failed"* ]]
    [[ "$output" == *"Bitwarden: flatpak install failed"* ]]
    [[ "$output" == *"Fix the cause and run ./install.sh --update to retry."* ]]
}

@test "summary prints no failure block when nothing failed" {
    run in_sub 'apps_summary_failures'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Setup hooks ----------------------------------------------------------------------
# sudo and the user-level tools log their calls to $CALLS; sudo fails when its arguments
# contain $SUDO_FAIL. systemctl reports only the SSH unit named in $SSH_ON as enabled/active;
# xdg-mime query prints $PDF_DEFAULT.
hook_stubs() {
    STUBS="$BATS_TEST_TMPDIR/stubs"
    CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$STUBS"
    : >"$CALLS"
    cat >"$STUBS/sudo" <<'STUB'
#!/bin/sh
echo "sudo $*" >>"$CALLS"
case "$*" in *"${SUDO_FAIL:-@@none@@}"*) exit 1 ;; esac
exit 0
STUB
    for t in xdg-mime rustup; do
        printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n[ "$*" = "default" ] && printf "%%s" "${RUSTUP_DEFAULT:-}"\n[ "$1" = "query" ] && printf "%%s" "${PDF_DEFAULT:-}"\nexit 0\n' "$t" >"$STUBS/$t"
    done
    printf '#!/bin/sh\necho "id $*" >>"$CALLS"\necho "${ID_GROUPS:-wheel}"\n' >"$STUBS/id"
    printf '#!/bin/sh\nexit "${FINDMNT_RC:-1}"\n' >"$STUBS/findmnt"
    printf '#!/bin/sh\necho "systemctl $*" >>"$CALLS"\ncase "$*" in *ssh*) case "$*" in *"${SSH_ON:-@@none@@}"*) exit 0 ;; esac; exit 1 ;; esac\nexit 0\n' >"$STUBS/systemctl"
    chmod +x "$STUBS"/*
}

in_hooks() {
    NUSKU_ETC="$BATS_TEST_TMPDIR/etc" NUSKU_BOOT="$BATS_TEST_TMPDIR/boot" USER=tester \
        HOME="$BATS_TEST_TMPDIR/home" PATH="$STUBS:$PATH" CALLS="$CALLS" \
        in_sub "source lib/packages.sh; source lib/backup.sh; source lib/dotfiles.sh; $1"
}

@test "hooks run only for selected apps" {
    hook_stubs
    run in_hooks "answers_set APPS docker; answers_set LANGS ''; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo systemctl enable docker.service' "$CALLS"
    ! grep -q ufw "$CALLS" || false
}

@test "docker hook adds the user to the group and leaves a note" {
    hook_stubs
    run in_hooks "answers_set APPS docker; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    grep -q 'sudo usermod -aG docker tester' "$CALLS"
    [[ "$output" == *"Notes:"* ]]
    [[ "$output" == *"You are in the docker group: that is root-equivalent. Log out and back in to use docker without sudo."* ]]
}

@test "docker hook skips usermod and the note when already in the group" {
    hook_stubs
    ID_GROUPS="wheel docker" run in_hooks "answers_set APPS 'docker firefox'; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    grep -q 'sudo systemctl enable docker.service' "$CALLS"
    ! grep -q usermod "$CALLS" || false
    [[ "$output" != *"Notes:"* ]]
}

@test "docker hook leaves no note when usermod fails" {
    hook_stubs
    SUDO_FAIL=usermod run in_hooks "answers_set APPS 'docker firefox'; apps_run_hooks; apps_summary_notes; printf 'fail=[%s]\n' \"\${NUSKU_APP_FAILURES[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" != *"Notes:"* ]]
    [[ "$output" == *"fail=[Docker + Compose: setup failed]"* ]]
}

@test "summary prints no notes when there are none" {
    run in_sub 'apps_summary_notes'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ufw hook opens LocalSend's port when LocalSend is selected" {
    hook_stubs
    run in_hooks "answers_set APPS 'localsend ufw'; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo ufw allow 53317/tcp comment LocalSend' "$CALLS"
    grep -q 'sudo ufw allow 53317/udp comment LocalSend' "$CALLS"
}

@test "ufw hook leaves the port closed without LocalSend" {
    hook_stubs
    run in_hooks "answers_set APPS ufw; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo ufw default deny incoming' "$CALLS"
    grep -q 'sudo ufw default allow outgoing' "$CALLS"
    ! grep -q 53317 "$CALLS" || false
}

@test "calendar hook explains the keyring and Online Accounts" {
    hook_stubs
    run in_hooks "answers_set APPS 'calendar firefox'; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    [[ "$output" == *"open Online Accounts to add Google or Nextcloud"* ]]
}

@test "sunshine hook starts it at login and explains pairing" {
    hook_stubs
    run in_hooks "answers_set APPS 'sunshine firefox'; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    grep -qx 'sudo systemctl enable --now avahi-daemon.service' "$CALLS"
    grep -qx 'systemctl --user enable app-dev.lizardbyte.app.Sunshine.service' "$CALLS"
    [[ "$output" == *"https://localhost:47990"* ]]
}

@test "ufw hook opens Sunshine's streaming ports, not its settings page" {
    hook_stubs
    run in_hooks "answers_set APPS 'sunshine ufw'; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo ufw allow 47984,47989,48010/tcp comment Sunshine' "$CALLS"
    grep -q 'sudo ufw allow 47998:48000,48002,48010/udp comment Sunshine' "$CALLS"
    grep -q 'sudo ufw allow 5353/udp' "$CALLS"
    ! grep -q 47990 "$CALLS" || false
}

@test "ufw hook leaves Sunshine's ports closed without Sunshine" {
    hook_stubs
    run in_hooks "answers_set APPS ufw; apps_run_hooks"
    ! grep -q Sunshine "$CALLS" || false
}

@test "ufw hook uses --force enable and enables the service" {
    hook_stubs
    run in_hooks "answers_set APPS ufw; apps_run_hooks"
    grep -q 'sudo ufw --force enable' "$CALLS"
    grep -q 'sudo systemctl enable ufw.service' "$CALLS"
}

@test "ufw hook keeps SSH open when sshd is enabled" {
    hook_stubs
    SSH_ON=sshd.service run in_hooks "answers_set APPS ufw; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo ufw allow 22/tcp comment SSH' "$CALLS"
    [ "$(grep -n 'ufw allow 22/tcp' "$CALLS" | cut -d: -f1)" -lt "$(grep -n 'ufw --force enable' "$CALLS" | cut -d: -f1)" ]
}

@test "ufw hook keeps SSH open when only an SSH socket is enabled" {
    local unit
    for unit in sshd.socket ssh.socket; do
        hook_stubs
        SSH_ON="$unit" run in_hooks "answers_set APPS ufw; apps_run_hooks"
        [ "$status" -eq 0 ]
        grep -q 'sudo ufw allow 22/tcp comment SSH' "$CALLS" || { echo "no SSH rule for $unit"; false; }
    done
}

@test "ufw hook adds no SSH rule when sshd is off" {
    hook_stubs
    run in_hooks "answers_set APPS ufw; apps_run_hooks"
    [ "$status" -eq 0 ]
    ! grep -q '22/tcp' "$CALLS" || false
    grep -q 'sudo ufw --force enable' "$CALLS"
}

@test "flatpak hook adds the Flathub remote" {
    hook_stubs
    run in_hooks "answers_set APPS flatpak; apps_run_hooks"
    grep -q 'sudo flatpak remote-add --if-not-exists --system flathub' "$CALLS"
}

@test "gamemode hook joins the group unless already a member" {
    hook_stubs
    run in_hooks "answers_set APPS gamemode; apps_run_hooks"
    grep -q 'sudo usermod -aG gamemode tester' "$CALLS"
    : >"$CALLS"
    ID_GROUPS="wheel gamemode" run in_hooks "answers_set APPS gamemode; apps_run_hooks"
    ! grep -q usermod "$CALLS" || false
}

@test "zathura hook makes it the PDF viewer, as the user" {
    hook_stubs
    run in_hooks "answers_set APPS zathura; apps_run_hooks"
    grep -q '^xdg-mime query default application/pdf' "$CALLS"
    grep -q '^xdg-mime default org.pwmt.zathura.desktop application/pdf' "$CALLS"
    ! grep -q 'sudo xdg-mime' "$CALLS" || false
}

@test "zathura hook keeps an existing PDF default" {
    hook_stubs
    PDF_DEFAULT=org.gnome.Evince.desktop run in_hooks "answers_set APPS zathura; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q '^xdg-mime query default application/pdf' "$CALLS"
    ! grep -q '^xdg-mime default' "$CALLS" || false
}

# fake_desktop FILE...: installed .desktop files, in a data dir passed as XDG_DATA_DIRS="$SHARE".
fake_desktop() {
    SHARE="$BATS_TEST_TMPDIR/share"
    mkdir -p "$SHARE/applications"
    local f
    for f in "$@"; do : >"$SHARE/applications/$f"; done
}

@test "every browser in the catalogue has a desktop file" {
    run in_sub 'for id in $(awk -F"|" "\$1 == \"app\" && \$7 ~ /browser/ { print \$3 }" "$NUSKU_APPS_LIST"); do apps_browser_desktop "$id" || echo "missing $id"; done'
    [ "$status" -eq 0 ]
    [[ "$output" != *missing* ]]
    [[ "$output" == *firefox.desktop* ]]
}

@test "no browser picked: summary note" {
    hook_stubs
    run in_hooks "answers_set APPS discord; apps_run_hooks; apps_summary_notes"
    [[ "$output" == *"No web browser is installed"* ]]
    ! grep -q '^xdg-mime default' "$CALLS" || false
}

@test "picked browser that failed to install: no extra note (the failure list covers it)" {
    hook_stubs
    fake_desktop
    XDG_DATA_DIRS="$SHARE" run in_hooks "answers_set APPS brave; apps_run_hooks; apps_summary_notes"
    [[ "$output" != *"No web browser"* ]]
    ! grep -q '^xdg-mime default' "$CALLS" || false
}

@test "browser becomes the default for web links when none is set" {
    hook_stubs
    fake_desktop brave-browser.desktop
    XDG_DATA_DIRS="$SHARE" run in_hooks "answers_set APPS 'zen brave'; apps_run_hooks"
    grep -qxF 'xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https text/html' "$CALLS"
}

@test "browser replaces a default that is no longer installed" {
    hook_stubs
    fake_desktop chromium.desktop
    PDF_DEFAULT=firefox.desktop XDG_DATA_DIRS="$SHARE" run in_hooks "answers_set APPS chromium; apps_run_hooks"
    grep -q '^xdg-mime default chromium.desktop x-scheme-handler/http' "$CALLS"
}

@test "an installed default browser is kept" {
    hook_stubs
    fake_desktop chromium.desktop firefox.desktop
    PDF_DEFAULT=firefox.desktop XDG_DATA_DIRS="$SHARE" run in_hooks "answers_set APPS chromium; apps_run_hooks"
    [ "$status" -eq 0 ]
    ! grep -q '^xdg-mime default' "$CALLS" || false
}

@test "snapper hook with an existing root config still enables the timers and grub" {
    hook_stubs
    mkdir -p "$BATS_TEST_TMPDIR/etc/snapper/configs" "$BATS_TEST_TMPDIR/boot/grub"
    : >"$BATS_TEST_TMPDIR/etc/snapper/configs/root"
    : >"$BATS_TEST_TMPDIR/boot/grub/grub.cfg"
    FINDMNT_RC=0 NUSKU_ROOT_FSTYPE=btrfs run in_hooks "answers_set APPS snapper; apps_run_hooks; printf 'fail=[%s]\n' \"\${NUSKU_APP_FAILURES[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"already"* ]]
    [[ "$output" == *"fail=[]"* ]]
    local want=(
        'sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service'
        "sudo grub-mkconfig -o $BATS_TEST_TMPDIR/boot/grub/grub.cfg"
    )
    mapfile -t got <"$CALLS"
    [ "${got[*]}" = "${want[*]}" ] || { printf '%s\n' "${got[@]}"; false; }
}

@test "snapper hook stops mid-dance when create-config fails" {
    hook_stubs
    SUDO_FAIL=create-config FINDMNT_RC=0 NUSKU_ROOT_FSTYPE=btrfs run in_hooks "answers_set APPS snapper; apps_hook_snapper; echo \"rc=\$?\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1"* ]]
    grep -q 'sudo snapper -c root create-config /' "$CALLS"
    ! grep -q 'btrfs subvolume delete' "$CALLS" || false
    ! grep -q 'systemctl enable' "$CALLS" || false
}

@test "snapper hook does the umount dance when /.snapshots is mounted" {
    hook_stubs
    mkdir -p "$BATS_TEST_TMPDIR/boot/grub"
    : >"$BATS_TEST_TMPDIR/boot/grub/grub.cfg"
    FINDMNT_RC=0 NUSKU_ROOT_FSTYPE=btrfs run in_hooks "answers_set APPS snapper; apps_run_hooks"
    [ "$status" -eq 0 ]
    local want=(
        'sudo umount /.snapshots'
        'sudo rmdir /.snapshots'
        'sudo snapper -c root create-config /'
        'sudo btrfs subvolume delete /.snapshots'
        'sudo mkdir /.snapshots'
        'sudo mount -a'
        'sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service'
        "sudo grub-mkconfig -o $BATS_TEST_TMPDIR/boot/grub/grub.cfg"
    )
    mapfile -t got <"$CALLS"
    [ "${got[*]}" = "${want[*]}" ] || { printf '%s\n' "${got[@]}"; false; }
}

@test "snapper hook only creates the config when /.snapshots is not mounted" {
    hook_stubs
    NUSKU_ROOT_FSTYPE=btrfs run in_hooks "answers_set APPS snapper; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q 'sudo snapper -c root create-config /' "$CALLS"
    ! grep -q umount "$CALLS" || false
    ! grep -q grub-mkconfig "$CALLS" || false
    grep -q 'sudo systemctl enable snapper-timeline.timer' "$CALLS"
}

@test "snapper hook does nothing on ext4" {
    hook_stubs
    NUSKU_ROOT_FSTYPE=ext4 run in_hooks "answers_set APPS snapper; apps_hook_snapper"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "snapper picked on a non-btrfs root is skipped with a summary note" {
    hook_stubs
    NUSKU_ROOT_FSTYPE=ext4 run in_hooks "answers_set APPS snapper; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
    [[ "$output" == *"Notes:"*"Snapper was skipped: / is not btrfs."* ]]
}

@test "no btrfs note when snapper is not picked" {
    hook_stubs
    NUSKU_ROOT_FSTYPE=ext4 run in_hooks "answers_set APPS gimp; apps_run_hooks; apps_summary_notes"
    [ "$status" -eq 0 ]
    [[ "$output" != *"btrfs"* ]]
}

@test "a failing hook is recorded and later hooks still run" {
    hook_stubs
    SUDO_FAIL="enable docker.service" run in_hooks "answers_set APPS 'docker zathura'; apps_run_hooks; printf '%s\n' \"\${NUSKU_APP_FAILURES[@]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Docker + Compose: setup failed"* ]]
    grep -q 'xdg-mime default org.pwmt.zathura.desktop' "$CALLS"
}

@test "rust hook sets stable only when no default toolchain" {
    hook_stubs
    RUSTUP_DEFAULT="" run in_hooks "answers_set APPS ''; answers_set LANGS rust; apps_run_hooks"
    [ "$status" -eq 0 ]
    grep -q '^rustup default stable' "$CALLS"
    grep -q '^rustup component add rust-analyzer rustfmt' "$CALLS"
    : >"$CALLS"
    RUSTUP_DEFAULT="stable-x86_64-unknown-linux-gnu (default)" run in_hooks "answers_set APPS ''; answers_set LANGS rust; apps_run_hooks"
    ! grep -q '^rustup default stable' "$CALLS" || false
    grep -q '^rustup component add rust-analyzer rustfmt' "$CALLS"
}

@test "hooks run apps in catalogue order, then languages" {
    hook_stubs
    run in_hooks "answers_set APPS 'ufw zathura docker'; answers_set LANGS rust; apps_run_hooks"
    local order
    order="$(grep -oE 'docker.service|zathura|ufw.service|rustup default stable' "$CALLS" | tr '\n' ',')"
    [ "$order" = "docker.service,zathura,ufw.service,rustup default stable," ]
}

@test "apps_write_nvim_languages writes selected languages in catalogue order" {
    run in_sub "answers_set LANGS 'rust python'; apps_write_nvim_languages '$BATS_TEST_TMPDIR/langs.lua'"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$BATS_TEST_TMPDIR/langs.lua")" = "-- Generated by Nusku from LANGS in ~/.config/nusku/answers; do not edit." ]
    [ "$(tail -n1 "$BATS_TEST_TMPDIR/langs.lua")" = 'return { "python", "rust" }' ]
    [ "$(wc -l <"$BATS_TEST_TMPDIR/langs.lua")" -eq 2 ]
}

@test "apps_write_nvim_languages writes an empty table with no languages" {
    printf 'return { "go" }\n' >"$BATS_TEST_TMPDIR/langs.lua"
    run in_sub "answers_set LANGS ''; apps_write_nvim_languages '$BATS_TEST_TMPDIR/sub/langs.lua'; apps_write_nvim_languages '$BATS_TEST_TMPDIR/langs.lua'"
    [ "$status" -eq 0 ]
    [ "$(tail -n1 "$BATS_TEST_TMPDIR/langs.lua")" = 'return {}' ]
    [ "$(tail -n1 "$BATS_TEST_TMPDIR/sub/langs.lua")" = 'return {}' ]
}

@test "every catalogue language is mapped in nusku.languages" {
    local f=config/nvim/lua/nusku/languages.lua
    [ -f "$f" ]
    # Keys of the extras table: lines like `  python = { ... },` or `  lua = false,`.
    keys="$(sed -n '/^M.extras = {/,/^}/p' "$f" | sed -nE 's/^  ([a-z]+) = .*/\1/p' | sort | tr '\n' ' ')"
    langs="$(in_sub 'apps_langs' | sort | tr '\n' ' ')"
    [ -n "$langs" ]
    [ "$keys" = "$langs" ] || { echo "keys: $keys"; echo "langs: $langs"; false; }
}

@test "nusku.languages builds imports without plugins installed" {
    mkdir -p "$BATS_TEST_TMPDIR/cfg/nusku"
    printf 'return { "python", "go" }\n' >"$BATS_TEST_TMPDIR/cfg/nusku/nvim-languages.lua"
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg" run nvim --headless --clean "+set rtp^=$PWD/config/nvim" \
        "+lua io.write(vim.inspect(require('nusku.languages').imports()))" +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *'"lazyvim.plugins.extras.lang.python"'* ]]
    [[ "$output" == *'"lazyvim.plugins.extras.lang.go"'* ]]
    [[ "$output" != *"extras.lang.rust"* ]]
}

@test "nusku.languages imports nothing without the languages file" {
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/empty" run nvim --headless --clean "+set rtp^=$PWD/config/nvim" \
        "+lua io.write(vim.inspect(require('nusku.languages').imports()))" +qa
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

# Stub nvim plus a timeout stub that records its arguments, then runs the command (or fails
# with TIMEOUT_RC, e.g. 124, as if the time limit was hit).
nvim_stubs() {
    hook_stubs
    printf '#!/bin/sh\necho "nvim $*" >>"$CALLS"\n[ -t 0 ] && echo "nvim stdin is a tty" >>"$CALLS"\nexit "${NVIM_RC:-0}"\n' >"$STUBS/nvim"
    printf '#!/bin/sh\necho "timeout $*" >>"$CALLS"\n[ -z "${TIMEOUT_RC:-}" ] || exit "$TIMEOUT_RC"\nshift\nexec "$@"\n' >"$STUBS/timeout"
    chmod +x "$STUBS/nvim" "$STUBS/timeout"
    export NUSKU_CONFIG_DIR="$BATS_TEST_TMPDIR/nuskucfg"
}

@test "neovim hook writes the languages file and runs the headless sync with a time limit" {
    nvim_stubs
    run in_hooks "answers_set APPS neovim; answers_set LANGS 'go python'; apps_run_hooks; printf 'fail=[%s]\n' \"\${NUSKU_APP_FAILURES[*]}\""
    [ "$status" -eq 0 ]
    [ "$(tail -n1 "$NUSKU_CONFIG_DIR/nvim-languages.lua")" = 'return { "python", "go" }' ]
    grep -qx "timeout 40m nvim --headless +lua require('nusku.sync').run() +cquit 2" "$CALLS"
    grep -qx "nvim --headless +lua require('nusku.sync').run() +cquit 2" "$CALLS"
    ! grep -q "stdin is a tty" "$CALLS" || false
    [[ "$output" == *"fail=[]"* ]]
}

@test "neovim hook links ~/.config/nvim, backing up what was there" {
    nvim_stubs
    mkdir -p "$BATS_TEST_TMPDIR/home/.config/nvim"
    echo mine >"$BATS_TEST_TMPDIR/home/.config/nvim/init.lua"
    run in_hooks "answers_set APPS neovim; answers_set LANGS ''; apps_run_hooks"
    [ "$status" -eq 0 ]
    [ "$(readlink "$BATS_TEST_TMPDIR/home/.config/nvim")" = "$PWD/config/nvim" ]
    run grep -rlx mine "$XDG_STATE_HOME/nusku"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/.config/nvim/init.lua" ]]
}

@test "without neovim picked ~/.config/nvim is left alone" {
    nvim_stubs
    mkdir -p "$BATS_TEST_TMPDIR/home/.config/nvim"
    echo mine >"$BATS_TEST_TMPDIR/home/.config/nvim/init.lua"
    run in_hooks "answers_set APPS gimp; answers_set LANGS python; apps_run_hooks"
    [ "$status" -eq 0 ]
    [ ! -L "$BATS_TEST_TMPDIR/home/.config/nvim" ]
    [ "$(cat "$BATS_TEST_TMPDIR/home/.config/nvim/init.lua")" = mine ]
    ! grep -q '^nvim ' "$CALLS" || false
}

@test "the dotfile manifest does not link ~/.config/nvim" {
    ! grep -q 'config/nvim' config/links.txt || false
}

@test "neovim hook fails and is recorded when the sync exits non-zero" {
    nvim_stubs
    NVIM_RC=2 run in_hooks "answers_set APPS neovim; answers_set LANGS ''; apps_hook_neovim; echo \"rc=\$?\"; apps_run_hooks; printf 'fail=[%s]\n' \"\${NUSKU_APP_FAILURES[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" == *"fail=[Neovim (LazyVim): setup failed]"* ]]
}

@test "neovim hook fails and is recorded when the sync times out" {
    nvim_stubs
    TIMEOUT_RC=124 run in_hooks "answers_set APPS neovim; answers_set LANGS ''; apps_hook_neovim; echo \"rc=\$?\"; apps_run_hooks; printf 'fail=[%s]\n' \"\${NUSKU_APP_FAILURES[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=124"* ]]
    [[ "$output" == *"fail=[Neovim (LazyVim): setup failed]"* ]]
    ! grep -q '^nvim ' "$CALLS" || false
}

@test "artcraft group lists 13 apps in order" {
    run in_sub 'apps_in_group artcraft | tr "\n" " "'
    [ "$status" -eq 0 ]
    [ "$output" = "photocraft vectorcraft filmcraft lightcraft pdfcraft effectcraft designcraft figcraft wordcraft soundcraft deckcraft cadcraft gridcraft " ]
    run in_sub 'apps_starred'
    [[ " $output " != *craft* ]]
}

@test "artcraft picks add the launcher once, first" {
    run in_sub 'answers_set APPS "photocraft pdfcraft"; apps_batches'
    [ "$status" -eq 0 ]
    [ "$output" = $'artcraft launcher craft-launcher\nartcraft photocraft photocraft\nartcraft pdfcraft pdfcraft' ]
}

@test "no artcraft picks, no launcher" {
    run in_sub 'answers_set APPS "firefox"; apps_batches'
    [ "$status" -eq 0 ]
    [[ "$output" != *artcraft* ]]
}
