#!/usr/bin/env bash
# Optional app and language catalogue (packages/apps.list), parsed with awk, never sourced. Sourced, not executed.
# Needs lib/log.sh (die) and lib/answers.sh (answers_get); the install and hook functions also
# use lib/packages.sh (pkg_*) and lib/dotfiles.sh (link_file).

: "${NUSKU_APPS_LIST:=${NUSKU_ROOT:-.}/packages/apps.list}"

# apps_groups: group ids in file order.
apps_groups() {
    awk -F'|' '$1 == "group" { print $2 }' "$NUSKU_APPS_LIST"
}

# apps_group_label GROUP
apps_group_label() {
    awk -F'|' -v id="$1" '$1 == "group" && $2 == id { print $3; exit }' "$NUSKU_APPS_LIST"
}

# apps_root_is_btrfs: status 0 when / is btrfs (NUSKU_ROOT_FSTYPE overrides the probe, for tests).
apps_root_is_btrfs() {
    [ "${NUSKU_ROOT_FSTYPE:-$(findmnt -no FSTYPE / 2>/dev/null)}" = btrfs ]
}

# apps_in_group GROUP: app ids in file order; btrfs-only apps appear only on a btrfs root.
apps_in_group() {
    local skip=1
    ! apps_root_is_btrfs || skip=0
    awk -F'|' -v g="$1" -v skip="$skip" '
        $1 == "app" && $2 == g {
            if (skip && (","$7",") ~ /,btrfs,/) next
            print $3
        }' "$NUSKU_APPS_LIST"
}

# apps_label ID: label of an app or a language.
apps_label() {
    awk -F'|' -v id="$1" '
        $1 == "app" && $3 == id { print $5; exit }
        $1 == "lang" && $2 == id { print $3; exit }' "$NUSKU_APPS_LIST"
}

# apps_starred: space-separated ids of the pre-selected favourites.
apps_starred() {
    awk -F'|' '$1 == "app" && $4 == "*" { printf "%s%s", sep, $3; sep = " " } END { print "" }' "$NUSKU_APPS_LIST"
}

# apps_langs: language ids in file order.
apps_langs() {
    awk -F'|' '$1 == "lang" { print $2 }' "$NUSKU_APPS_LIST"
}

# apps_packages ID: package tokens of an app or language, one per line.
apps_packages() {
    awk -F'|' -v id="$1" '
        $1 == "app" && $3 == id { n = split($6, t, " "); for (i = 1; i <= n; i++) print t[i]; exit }
        $1 == "lang" && $2 == id { n = split($4, t, " "); for (i = 1; i <= n; i++) print t[i]; exit }' "$NUSKU_APPS_LIST"
}

# apps_has_flag ID FLAG: status 0 when the app/language carries FLAG.
apps_has_flag() {
    awk -F'|' -v id="$1" -v flag="$2" '
        $1 == "app" && $3 == id { found = 1; f = $7 }
        $1 == "lang" && $2 == id { found = 1; f = $5 }
        found { exit ((","f",") ~ ("," flag ",") ? 0 : 1) }
        END { if (!found) exit 1 }' "$NUSKU_APPS_LIST"
}

# apps_validate_answers: every id in APPS and LANGS must exist in the catalogue.
apps_validate_answers() {
    local id
    for id in $(answers_get APPS); do
        awk -F'|' -v id="$id" '$1 == "app" && $3 == id { f = 1 } END { exit !f }' "$NUSKU_APPS_LIST" ||
            die "answers: unknown app '$id' in APPS; see packages/apps.list"
    done
    for id in $(answers_get LANGS); do
        awk -F'|' -v id="$id" '$1 == "lang" && $2 == id { f = 1 } END { exit !f }' "$NUSKU_APPS_LIST" ||
            die "answers: unknown language '$id' in LANGS; see packages/apps.list"
    done
}

# --- Picker ---------------------------------------------------------------------------
# Working selections (space-padded id lists) while the picker runs.
_APPS_SEL=" "
_APPS_LANGS=" "

# _apps_pick_label ID: the checklist line of an app ("★ Label" for the favourites).
_apps_pick_label() {
    if apps_has_star "$1"; then
        printf '★ %s\n' "$(apps_label "$1")"
    else
        apps_label "$1"
    fi
}

# apps_has_star ID: status 0 when the app is a pre-selected favourite.
apps_has_star() {
    awk -F'|' -v id="$1" '$1 == "app" && $3 == id && $4 == "*" { f = 1 } END { exit !f }' "$NUSKU_APPS_LIST"
}

# _apps_count GROUP: "selected/total" for a group of apps.
_apps_count() {
    local id n=0 t=0
    for id in $(apps_in_group "$1"); do
        t=$((t + 1))
        case "$_APPS_SEL" in *" $id "*) n=$((n + 1)) ;; esac
    done
    printf '%s/%s' "$n" "$t"
}

# _apps_gum_status STATUS: gum exits 1 on Esc (handled by the caller) and 130 on Ctrl+C, which
# cancels the whole install.
_apps_gum_status() {
    [ "$1" -ne 130 ] || die "Cancelled"
}

# _apps_pick_group GROUP: checklist over one group. Esc changes nothing; an empty reply or a
# ticked "None" clears the group.
_apps_pick_group() {
    local g="$1" id line out pre="" sel=" "
    local -a ids=() lines=()
    for id in $(apps_in_group "$g"); do
        ids+=("$id")
        lines+=("$(_apps_pick_label "$id")")
        case "$_APPS_SEL" in *" $id "*) pre="${pre:+$pre,}${lines[-1]}" ;; esac
    done
    out="$(gum choose --no-limit --header "$(apps_group_label "$g") — space toggles, ctrl+a selects all, enter confirms" \
        --selected "$pre" None "${lines[@]}")" || {
        _apps_gum_status "$?"
        return 0
    }
    while IFS= read -r line; do
        for id in "${ids[@]}"; do
            [ "$(_apps_pick_label "$id")" = "$line" ] && sel="$sel$id "
        done
    done <<<"$out"
    case $'
'"$out"$'
' in *$'
None
'*) sel=" " ;; esac
    for id in "${ids[@]}"; do
        _APPS_SEL="${_APPS_SEL// $id / }"
    done
    _APPS_SEL="$_APPS_SEL${sel# }"
}

# _apps_pick_langs: checklist over the languages. Esc changes nothing; an empty reply or a
# ticked "None" clears them.
_apps_pick_langs() {
    local id line out pre="" sel=" "
    local -a ids=() labels=()
    for id in $(apps_langs); do
        ids+=("$id")
        labels+=("$(apps_label "$id")")
        case "$_APPS_LANGS" in *" $id "*) pre="${pre:+$pre,}${labels[-1]}" ;; esac
    done
    out="$(gum choose --no-limit --header "Languages — runtimes, tools and Neovim support" \
        --selected "$pre" None "${labels[@]}")" || {
        _apps_gum_status "$?"
        return 0
    }
    while IFS= read -r line; do
        for id in "${ids[@]}"; do
            [ "$(apps_label "$id")" = "$line" ] && sel="$sel$id "
        done
    done <<<"$out"
    case $'
'"$out"$'
' in *$'
None
'*) sel=" " ;; esac
    _APPS_LANGS="$sel"
}

# apps_ask: interactive picker; stores APPS (catalogue order) and LANGS. Starts from the stored
# picks when the keys exist, else from the starred apps and no languages.
apps_ask() {
    local g id choice label menu_hdr="Optional apps — pick a group to change, then Done"
    if [ -n "${NUSKU_ANSWERS[APPS]+x}" ]; then
        _APPS_SEL=" ${NUSKU_ANSWERS[APPS]} "
    else
        _APPS_SEL=" $(apps_starred) "
    fi
    _APPS_LANGS=" ${NUSKU_ANSWERS[LANGS]:-} "
    local -a menu=()
    while :; do
        menu=()
        for g in $(apps_groups); do
            menu+=("$(apps_group_label "$g") ($(_apps_count "$g"))")
        done
        menu+=("Done")
        choice="$(gum choose --header "$menu_hdr" "${menu[@]}")" || {
            _apps_gum_status "$?"
            break
        }
        [ "$choice" != "Done" ] || break
        for g in $(apps_groups); do
            label="$(apps_group_label "$g") ($(_apps_count "$g"))"
            if [ "$choice" = "$label" ]; then
                _apps_pick_group "$g"
                [ "$g" != dev ] || _apps_pick_langs
                break
            fi
        done
    done
    local apps="" langs=""
    while IFS= read -r id; do
        case "$_APPS_SEL" in *" $id "*) apps="${apps:+$apps }$id" ;; esac
    done < <(awk -F'|' '$1 == "app" { print $3 }' "$NUSKU_APPS_LIST")
    for id in $(apps_langs); do
        case "$_APPS_LANGS" in *" $id "*) langs="${langs:+$langs }$id" ;; esac
    done
    answers_set APPS "$apps"
    answers_set LANGS "$langs"
    log_info "Apps: ${apps:-none}"
    log_info "Languages: ${langs:-none}"
}

# apps_default_missing: non-interactive runs treat unsaved APPS/LANGS as "none".
apps_default_missing() {
    [ "${NUSKU_NONINTERACTIVE:-0}" = "1" ] || return 0
    if [ -z "${NUSKU_ANSWERS[APPS]+x}" ]; then
        answers_set APPS ""
        log_info "No optional apps selected (add some with ./install.sh --apps)"
    fi
    if [ -z "${NUSKU_ANSWERS[LANGS]+x}" ]; then
        answers_set LANGS ""
    fi
}

# --- Installing the picks -------------------------------------------------------------
# Optional installs that fail are listed here ("<label>: <what failed>") and shown in the
# summary. Update it only from functions called directly: $(...) runs in a subshell.
NUSKU_APP_FAILURES=()

# apps_gpu32 GPU NVIDIA_MODULE: the 32-bit driver tokens Steam needs, space-separated.
apps_gpu32() {
    local gpu="${1:-}" mod="${2:-}" igpu="" nv=""
    case "$gpu" in
        amd | hybrid-amd) igpu="lib32-mesa lib32-vulkan-radeon" ;;
        intel | hybrid-intel) igpu="lib32-mesa lib32-vulkan-intel" ;;
        vm) igpu="lib32-mesa lib32-vulkan-swrast" ;;
    esac
    case "$gpu" in
        nvidia | hybrid-*)
            if [ "$mod" = proprietary ]; then
                nv="aur:lib32-nvidia-580xx-utils"
            else
                nv="lib32-nvidia-utils"
            fi
            ;;
    esac
    printf '%s\n' "${igpu:+$igpu }$nv" | sed 's/ *$//'
}

# _apps_selected [say]: the picked app and language ids that apply here, one per line; a
# btrfs-only app on another filesystem is skipped (and logged when asked to "say").
_apps_selected() {
    local id
    for id in $(answers_get APPS); do
        if apps_has_flag "$id" btrfs && ! apps_root_is_btrfs; then
            [ "${1:-}" != say ] || log_info "Skipping $(apps_label "$id"): / is not btrfs"
            continue
        fi
        printf '%s\n' "$id"
    done
    for id in $(answers_get LANGS); do
        printf '%s\n' "$id"
    done
}

# apps_needs_multilib: status 0 when a selected app needs the multilib repo.
apps_needs_multilib() {
    local id
    while IFS= read -r id; do
        if apps_has_flag "$id" multilib || apps_has_flag "$id" gpu32; then
            return 0
        fi
    done < <(_apps_selected)
    return 1
}

# apps_batches GPU NVIDIA_MODULE: what to install, one line each: "repo NAME", "aur APP_ID NAME",
# "flatpak APP_ID ID" or "artcraft APP_ID REPO" (launcher line first). The gpu32 app also gets the
# GPU's 32-bit driver; if that driver is an AUR package, the app's own packages join it in the
# AUR batch so they install in one transaction.
apps_batches() {
    local gpu="${1:-}" mod="${2:-}" id t force g32_done=0 flat=0 has_aur
    local -a lines=() own=() items=() g32=() art=()
    while IFS= read -r id; do
        items=()
        mapfile -t own < <(apps_packages "$id")
        force=0
        if [ "$g32_done" -eq 0 ] && apps_has_flag "$id" gpu32; then
            g32_done=1
            read -ra g32 <<<"$(apps_gpu32 "$gpu" "$mod")"
            has_aur=0
            for t in "${g32[@]}"; do
                case "$t" in aur:*) has_aur=1 ;; esac
                items+=("0 $t")
            done
            force="$has_aur"
        fi
        for t in "${own[@]}"; do
            items+=("$force $t")
        done
        for t in "${items[@]}"; do
            force="${t%% *}"
            t="${t#* }"
            case "$t" in
                flatpak:*)
                    flat=1
                    lines+=("flatpak $id ${t#flatpak:}")
                    ;;
                aur:*) lines+=("aur $id ${t#aur:}") ;;
                artcraft:*) art+=("artcraft $id ${t#artcraft:}") ;;
                *)
                    if [ "$force" = 1 ]; then
                        lines+=("aur $id $t")
                    else
                        lines+=("repo $t")
                    fi
                    ;;
            esac
        done
    done < <(_apps_selected say)
    [ "$flat" -eq 0 ] || lines+=("repo flatpak")
    [ "${#art[@]}" -eq 0 ] || lines+=("artcraft launcher craft-launcher" "${art[@]}")
    [ "${#lines[@]}" -eq 0 ] || printf '%s\n' "${lines[@]}"
}

# apps_install_aur_soft BATCHES: one helper call per app with all its AUR names; a failure is
# recorded in NUSKU_APP_FAILURES and the run goes on.
apps_install_aur_soft() {
    local kind id name helper list
    local -a order=()
    local -A names=()
    while read -r kind id name; do
        [ "$kind" = aur ] || continue
        [ -n "${names[$id]+x}" ] || order+=("$id")
        names[$id]="${names[$id]:-} $name"
    done <<<"$1"
    [ "${#order[@]}" -gt 0 ] || return 0
    helper="$(answers_get AUR_HELPER)"
    [ -n "$helper" ] || die "AUR_HELPER is not set"
    for id in "${order[@]}"; do
        # shellcheck disable=SC2086  # names are space-separated package names
        run_soft "$helper" -S --needed --noconfirm ${names[$id]} || {
            list="${names[$id]# }"
            NUSKU_APP_FAILURES+=("$(apps_label "$id"): ${list// /, } (AUR install failed)")
        }
    done
}

# apps_install_flatpak_soft BATCHES: add Flathub, then one soft install per flatpak line.
apps_install_flatpak_soft() {
    local kind id fid any=0
    while read -r kind id fid; do
        [ "$kind" = flatpak ] || continue
        if [ "$any" -eq 0 ]; then
            any=1
            pkg_flathub_remote || true
        fi
        pkg_install_flatpak "$fid" || NUSKU_APP_FAILURES+=("$(apps_label "$id"): $fid (Flatpak install failed)")
    done <<<"$1"
}

# apps_summary_failures: the "Not installed" block for the summary; nothing when all went well.
apps_summary_failures() {
    [ "${#NUSKU_APP_FAILURES[@]}" -gt 0 ] || return 0
    local f red="" off=""
    if [ -t 2 ]; then
        red=$'\033[31m'
        off=$'\033[0m'
    fi
    printf '\n%sNot installed (see the log):%s\n' "$red" "$off"
    for f in "${NUSKU_APP_FAILURES[@]}"; do
        printf '%s  - %s%s\n' "$red" "$f" "$off"
    done
    printf '%sFix the cause and run ./install.sh --update to retry.%s\n' "$red" "$off"
}

# --- Setup hooks ----------------------------------------------------------------------
# Plain sentences for the summary (added by hooks, shown under "Notes:").
NUSKU_APP_NOTES=()

# apps_summary_notes: the "Notes" block for the summary; nothing when there are none.
apps_summary_notes() {
    [ "${#NUSKU_APP_NOTES[@]}" -gt 0 ] || return 0
    local n
    printf '\nNotes:\n'
    for n in "${NUSKU_APP_NOTES[@]}"; do
        printf '  - %s\n' "$n"
    done
}

# _apps_user_in_group USER GROUP: status 0 when USER is a member of GROUP.
_apps_user_in_group() {
    local g
    for g in $(id -nG "$1"); do
        [ "$g" != "$2" ] || return 0
    done
    return 1
}

# _apps_join_group GROUP: add the current user to GROUP unless already in it.
_apps_join_group() {
    local user="${USER:-$(id -un)}"
    if _apps_user_in_group "$user" "$1"; then
        log_info "$user is already in the $1 group"
        return 0
    fi
    run_soft sudo usermod -aG "$1" "$user"
}

apps_hook_docker() {
    local user="${USER:-$(id -un)}"
    run_soft sudo systemctl enable docker.service || return 1
    # The note is only for a run that actually adds the user.
    if _apps_user_in_group "$user" docker; then
        log_info "$user is already in the docker group"
        return 0
    fi
    _apps_join_group docker || return 1
    NUSKU_APP_NOTES+=("You are in the docker group: that is root-equivalent. Log out and back in to use docker without sudo.")
}

# _apps_ssh_on: status 0 when the SSH server is enabled or running (service or socket-activated).
_apps_ssh_on() {
    local u
    for u in sshd.service sshd.socket ssh.socket; do
        if systemctl is-enabled "$u" >/dev/null 2>&1 || systemctl is-active "$u" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

apps_hook_ufw() {
    run_soft sudo ufw default deny incoming || return 1
    run_soft sudo ufw default allow outgoing || return 1
    case " $(answers_get APPS) " in
        *" localsend "*)
            run_soft sudo ufw allow 53317/tcp comment LocalSend || return 1
            run_soft sudo ufw allow 53317/udp comment LocalSend || return 1
            ;;
    esac
    case " $(answers_get APPS) " in
        *" sunshine "*)
            # Streaming ports only; the settings page (47990) stays reachable from this PC alone.
            run_soft sudo ufw allow 47984,47989,48010/tcp comment Sunshine || return 1
            run_soft sudo ufw allow 47998:48000,48002,48010/udp comment Sunshine || return 1
            run_soft sudo ufw allow 5353/udp comment "Sunshine discovery (mDNS)" || return 1
            ;;
    esac
    if _apps_ssh_on; then
        log_info "sshd is enabled: allowing SSH (22/tcp) through UFW"
        run_soft sudo ufw allow 22/tcp comment SSH || return 1
    fi
    run_soft sudo ufw --force enable || return 1
    run_soft sudo systemctl enable ufw.service
}

# Sunshine's own user unit (alias sunshine.service); it starts with the Hyprland session.
NUSKU_SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"

# apps_hook_sunshine: start the stream host at every login, and say how to pair. Moonlight finds
# the host through Avahi (mDNS), which Arch installs but leaves off.
apps_hook_sunshine() {
    run_soft sudo systemctl enable --now avahi-daemon.service || return 1
    run_soft systemctl --user enable "$NUSKU_SUNSHINE_UNIT" || return 1
    NUSKU_APP_NOTES+=("Sunshine starts at login. Open https://localhost:47990 on this PC to create its login, then pair Moonlight with the PIN it shows.")
}

apps_hook_flatpak() {
    pkg_flathub_remote
}

apps_hook_gamemode() {
    _apps_join_group gamemode
}

apps_hook_snapper() {
    local boot="${NUSKU_BOOT:-/boot}"
    apps_root_is_btrfs || return 0
    if [ -e "${NUSKU_ETC:-/etc}/snapper/configs/root" ]; then
        log_info "Snapper is already configured for /; not creating it again"
    elif findmnt -n /.snapshots >/dev/null 2>&1; then
        # archinstall mounts its own @snapshots there; snapper wants to create the subvolume itself.
        run_soft sudo umount /.snapshots || return 1
        run_soft sudo rmdir /.snapshots || return 1
        run_soft sudo snapper -c root create-config / || return 1
        run_soft sudo btrfs subvolume delete /.snapshots || return 1
        run_soft sudo mkdir /.snapshots || return 1
        run_soft sudo mount -a || return 1
    else
        run_soft sudo snapper -c root create-config / || return 1
    fi
    run_soft sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service || return 1
    if [ -e "$boot/grub/grub.cfg" ]; then
        run_soft sudo grub-mkconfig -o "$boot/grub/grub.cfg"
    fi
}

# apps_hook_zathura: make Zathura the PDF viewer unless one is already set.
apps_hook_zathura() {
    if [ -n "$(xdg-mime query default application/pdf 2>/dev/null)" ]; then
        log_info "A PDF viewer is already the default; leaving it"
        return 0
    fi
    run_soft xdg-mime default org.pwmt.zathura.desktop application/pdf
}

apps_hook_rust() {
    if ! rustup default 2>/dev/null | grep -q '(default)'; then
        run_soft rustup default stable || return 1
    fi
    run_soft rustup component add rust-analyzer rustfmt
}

# apps_write_nvim_languages FILE: the picked languages as a Lua list (catalogue order), read by
# the Neovim config (lua/nusku/languages.lua) to choose LazyVim's language extras.
apps_write_nvim_languages() {
    local id list="" picked
    picked=" $(answers_get LANGS) "
    for id in $(apps_langs); do
        case "$picked" in *" $id "*) list="$list \"$id\"," ;; esac
    done
    mkdir -p "$(dirname "$1")"
    {
        printf '%s\n' "-- Generated by Nusku from LANGS in ~/.config/nusku/answers; do not edit."
        if [ -n "$list" ]; then
            printf 'return {%s }\n' "${list%,}"
        else
            printf 'return {}\n'
        fi
    } >"$1"
}

# apps_hook_neovim: link ~/.config/nvim to the repo's LazyVim config (only Neovim pickers get
# it; link_file backs up what was there), then install LazyVim's plugins (lazy-lock.json
# revisions), Mason tools and treesitter parsers headless, so the first launch has nothing left
# to download. Never hangs: "+cquit 2" exits if the +lua command errors outside run() (e.g.
# not our config), stdin is /dev/null and the whole sync gets 40 minutes (timeout exits 124).
apps_hook_neovim() {
    link_file "${NUSKU_ROOT:-.}/config/nvim" "$HOME/.config/nvim"
    apps_write_nvim_languages "${NUSKU_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nusku}/nvim-languages.lua" || return 1
    run_soft timeout 40m nvim --headless "+lua require('nusku.sync').run()" "+cquit 2" </dev/null
}

# --- Web browser ----------------------------------------------------------------------
# apps_browser_desktop ID: the .desktop file a browser app installs.
apps_browser_desktop() {
    case "$1" in
        firefox) echo firefox.desktop ;;
        chromium) echo chromium.desktop ;;
        brave) echo brave-browser.desktop ;;
        zen) echo zen.desktop ;;
        librewolf) echo io.gitlab.librewolf-community.desktop ;;
        *) return 1 ;;
    esac
}

# _apps_desktop_exists FILE: status 0 when FILE is in an applications dir (system, user, Flatpak).
_apps_desktop_exists() {
    local d dirs
    dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    dirs="$dirs:/var/lib/flatpak/exports/share:${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share"
    local IFS=:
    for d in $dirs; do
        [ -f "$d/applications/$1" ] && return 0
    done
    return 1
}

# apps_browser_setup: with no browser picked, add a summary note. Otherwise, when web links have
# no default or point at a browser that is gone, make the first installed picked browser the default.
apps_browser_setup() {
    local id desktop current first=""
    for id in $(answers_get APPS); do
        apps_has_flag "$id" browser || continue
        desktop="$(apps_browser_desktop "$id")" || continue
        if _apps_desktop_exists "$desktop"; then
            first="$desktop"
            break
        fi
    done
    if [ -z "$first" ]; then
        if ! _apps_any_browser_picked; then
            NUSKU_APP_NOTES+=("No web browser is installed, so links will not open. Pick one with ./install.sh --apps.")
        fi
        return 0
    fi
    current="$(xdg-mime query default x-scheme-handler/https 2>/dev/null || true)"
    if [ -n "$current" ] && _apps_desktop_exists "$current"; then
        log_info "Web links already open in $current; leaving it"
        return 0
    fi
    run_soft xdg-mime default "$first" x-scheme-handler/http x-scheme-handler/https text/html
}

# _apps_any_browser_picked: status 0 when APPS holds a browser (installed or not).
_apps_any_browser_picked() {
    local id
    for id in $(answers_get APPS); do
        apps_has_flag "$id" browser && return 0
    done
    return 1
}

# apps_run_hooks: run apps_hook_<id> for each selected app (catalogue order), then each selected
# language. A failing hook is recorded and the rest still run. A picked btrfs-only app on another
# filesystem gets a summary note instead.
apps_run_hooks() {
    local id fn sel
    for id in $(answers_get APPS); do
        if apps_has_flag "$id" btrfs && ! apps_root_is_btrfs; then
            NUSKU_APP_NOTES+=("$(apps_label "$id") was skipped: / is not btrfs.")
        fi
    done
    sel=" $(_apps_selected | tr '\n' ' ') "
    while IFS= read -r id; do
        case "$sel" in *" $id "*) ;; *) continue ;; esac
        fn="apps_hook_${id//-/_}"
        declare -F "$fn" >/dev/null || continue
        "$fn" || NUSKU_APP_FAILURES+=("$(apps_label "$id"): setup failed")
    done < <(awk -F'|' '$1 == "app" { print $3 } $1 == "lang" { print $2 }' "$NUSKU_APPS_LIST")
    apps_browser_setup
}
