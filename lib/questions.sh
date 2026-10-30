# Nusku - the install questions on one archinstall-style menu (lib/tui.sh).
# Needs lib/log.sh, lib/answers.sh (NUSKU_ANSWERS, NUSKU_ACCENTS), lib/apps.sh and lib/tui.sh.
# Sourced, not executed.
#
# Every setting is listed with its current value; Enter changes one, Install goes ahead, Esc asks
# whether to quit. Values start from the saved answers, else from sensible defaults.

# VALUE LABEL pairs for each question (install.sh's ask_menu uses them too).
Q_GPU=(
    amd "AMD graphics"
    intel "Intel graphics"
    nvidia "NVIDIA graphics (desktop)"
    hybrid-intel "Intel + NVIDIA laptop"
    hybrid-amd "AMD + NVIDIA laptop"
    vm "Virtual machine"
)
Q_NVIDIA=(
    open "open — RTX 20xx / GTX 16xx and newer (recommended)"
    proprietary "proprietary — legacy driver for GTX 900/10xx (AUR)"
)
Q_AUR=(
    paru "paru (recommended)"
    yay "yay"
)

# q_label VALUE PAIRS...: the label of VALUE (VALUE itself when it is not listed).
q_label() {
    local v="$1"
    shift
    while [ "$#" -ge 2 ]; do
        if [ "$1" = "$v" ]; then
            printf '%s\n' "$2"
            return 0
        fi
        shift 2
    done
    printf '%s\n' "$v"
}

# q_needs_nvidia: status 0 when the chosen graphics include an NVIDIA card.
q_needs_nvidia() {
    case "${NUSKU_ANSWERS[GPU]:-}" in nvidia | hybrid-*) return 0 ;; esac
    return 1
}

# questions_needed: status 0 when an interactive run still has questions to answer.
questions_needed() {
    local k
    for k in GPU AUR_HELPER ACCENT APPS; do
        [ -n "${NUSKU_ANSWERS[$k]+x}" ] || return 0
    done
    if q_needs_nvidia && [ -z "${NUSKU_ANSWERS[NVIDIA_MODULE]+x}" ]; then
        return 0
    fi
    return 1
}

# questions_defaults SUGGESTED_GPU: fill in whatever is not answered yet.
questions_defaults() {
    [ -n "${NUSKU_ANSWERS[GPU]+x}" ] || answers_set GPU "$1"
    [ -n "${NUSKU_ANSWERS[AUR_HELPER]+x}" ] || answers_set AUR_HELPER paru
    [ -n "${NUSKU_ANSWERS[ACCENT]+x}" ] || answers_set ACCENT blue
    _q_nvidia_fixup
}

# _q_nvidia_fixup: an NVIDIA choice needs a driver; other graphics must not keep one.
_q_nvidia_fixup() {
    if q_needs_nvidia; then
        [ -n "${NUSKU_ANSWERS[NVIDIA_MODULE]+x}" ] || answers_set NVIDIA_MODULE open
    else
        unset 'NUSKU_ANSWERS[NVIDIA_MODULE]'
    fi
}

# _q_pick KEY TITLE SUBTITLE PAIRS...: tui_choose over PAIRS; stores the value (Esc keeps it).
_q_pick() {
    local key="$1" title="$2" sub="$3" i=0 cur=0
    shift 3
    local -a values=() labels=()
    while [ "$#" -ge 2 ]; do
        values+=("$1")
        labels+=("$2")
        [ "$1" = "${NUSKU_ANSWERS[$key]:-}" ] && cur="$i"
        i=$((i + 1))
        shift 2
    done
    if tui_choose "$title" "$sub" "$cur" "${labels[@]}"; then
        answers_set "$key" "${values[$TUI_CHOICE]}"
    fi
}

# _q_apps_summary: "N apps, M languages" for the menu.
_q_apps_summary() {
    local a l
    if [ -z "${NUSKU_ANSWERS[APPS]+x}" ]; then
        a="$(wc -w <<<"$(apps_starred)")"
        printf '%s usual picks\n' "$a"
        return 0
    fi
    a="$(wc -w <<<"${NUSKU_ANSWERS[APPS]}")"
    l="$(wc -w <<<"${NUSKU_ANSWERS[LANGS]:-}")"
    printf '%s app%s, %s language%s\n' "$a" "$([ "$a" = 1 ] || echo s)" "$l" "$([ "$l" = 1 ] || echo s)"
}

# questions_menu SUGGESTED_GPU: the main menu. Returns when Install is picked, with every
# question answered (APPS falls back to the starred apps if the list was never opened).
questions_menu() {
    local suggested="$1" cur=0 a
    local -a rows=() lines=() gpu_pairs=() accent_pairs=()
    questions_defaults "$suggested"
    tui_open "${NUSKU_ANSWERS[ACCENT]}"
    while :; do
        _tui_style "${NUSKU_ANSWERS[ACCENT]}"
        rows=(gpu) lines=()
        lines+=("$(printf '%-16s %s' "Graphics" "$(q_label "${NUSKU_ANSWERS[GPU]}" "${Q_GPU[@]}")")")
        if q_needs_nvidia; then
            rows+=(nvidia)
            lines+=("$(printf '%-16s %s' "NVIDIA driver" "${NUSKU_ANSWERS[NVIDIA_MODULE]}")")
        fi
        rows+=(aur accent apps - install)
        lines+=("$(printf '%-16s %s' "AUR helper" "${NUSKU_ANSWERS[AUR_HELPER]}")")
        lines+=("$(printf '%-16s %s%s' "Accent colour" "$(tui_swatch "${NUSKU_ANSWERS[ACCENT]}")" "${NUSKU_ANSWERS[ACCENT]}")")
        lines+=("$(printf '%-16s %s' "Apps" "$(_q_apps_summary)")")
        lines+=("-" "$TUI_ACCENT""Install$TUI_RESET")
        [ "$cur" -lt "${#rows[@]}" ] || cur=$((${#rows[@]} - 1))
        if ! tui_menu "Nusku setup" "Check each setting, then pick Install." \
            "$([ "$TUI_ASCII" = 1 ] && echo 'up/down move · enter changes · esc quits' || echo '↑↓ move · enter changes · esc quits')" \
            "$cur" "${lines[@]}"; then
            # Input closed (no terminal): nobody can answer, so stop rather than ask forever.
            [ "$TUI_KEY" != eof ] || _tui_interrupt
            if tui_choose "Leave the installer?" "Nothing has been changed yet." 0 "Keep going" "Quit"; then
                if [ "$TUI_CHOICE" -eq 1 ]; then
                    _tui_interrupt
                fi
            fi
            continue
        fi
        cur="$TUI_CHOICE"
        case "${rows[$cur]}" in
            gpu)
                gpu_pairs=()
                for ((a = 0; a < ${#Q_GPU[@]}; a += 2)); do
                    if [ "${Q_GPU[$a]}" = "$suggested" ]; then
                        gpu_pairs+=("${Q_GPU[$a]}" "${Q_GPU[$((a + 1))]} (detected)")
                    else
                        gpu_pairs+=("${Q_GPU[$a]}" "${Q_GPU[$((a + 1))]}")
                    fi
                done
                _q_pick GPU "Graphics" "Picks the right drivers. The detected one is marked." "${gpu_pairs[@]}"
                _q_nvidia_fixup
                ;;
            nvidia) _q_pick NVIDIA_MODULE "NVIDIA driver" "Older cards (GTX 900/10xx) need the legacy one." "${Q_NVIDIA[@]}" ;;
            aur) _q_pick AUR_HELPER "AUR helper" "Installs community packages (AUR)." "${Q_AUR[@]}" ;;
            accent)
                accent_pairs=()
                for a in "${NUSKU_ACCENTS[@]}"; do
                    accent_pairs+=("$a" "$(tui_swatch "$a")$a")
                done
                _q_pick ACCENT "Accent colour" "Catppuccin Mocha. Change it later with nusku-theme." "${accent_pairs[@]}"
                ;;
            apps) apps_ask ;;
            install) break ;;
        esac
    done
    tui_close
    if [ -z "${NUSKU_ANSWERS[APPS]+x}" ]; then
        answers_set APPS "$(apps_starred)"
        answers_set LANGS ""
    fi
}
