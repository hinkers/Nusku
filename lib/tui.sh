# Nusku - keyboard menus for the installer, in the spirit of archinstall. Plain bash, no extra tools.
# Needs lib/log.sh (die). Sourced, not executed. Safe under `set -Eeuo pipefail`.
#
# Keys: ↑/↓ (or k/j) move, Home/End and PgUp/PgDn jump, Space ticks, Enter picks or opens,
# →/← open and close a group, Esc leaves without changes, Ctrl+C cancels the install.
#
# Reads keys from $NUSKU_TUI_IN and draws to $NUSKU_TUI_OUT (both /dev/tty by default), so the
# screens work while stdout is captured, and tests can feed keys from a file. On the Linux text
# console (TERM=linux), where fonts have few symbols and 16 colours, it draws plain ASCII.

_TUI_IN="" _TUI_OUT="" _TUI_STTY="" _TUI_DEPTH=0
TUI_KEY=""
TUI_CHOICE=0
_TUI_PENDING=""

# --- Colours and symbols ----------------------------------------------------------------

# _tui_style: set the escape codes and symbols for this terminal.
_tui_style() {
    local accent="${1:-blue}"
    TUI_RESET=$'\e[0m' TUI_BOLD=$'\e[1m' TUI_DIM=$'\e[2m'
    if [ "${TERM:-}" = linux ] || [ "${NUSKU_TUI_ASCII:-0}" = 1 ]; then
        TUI_ASCII=1
        TUI_ACCENT=$'\e[1;34m' TUI_GREEN=$'\e[32m' TUI_MUTED=$'\e[2m' TUI_TEXT=$'\e[0m'
        TUI_SYM_CUR=">" TUI_SYM_OPEN="v" TUI_SYM_SHUT=">" TUI_SYM_ON="[x]" TUI_SYM_OFF="[ ]"
        TUI_SYM_SOME="[-]" TUI_SYM_PICK="(*)" TUI_SYM_NOPICK="( )" TUI_SYM_LINE="-" TUI_SYM_STAR="*"
        TUI_SYM_SWATCH=""
    else
        TUI_ASCII=0
        TUI_ACCENT="$TUI_BOLD$(_tui_hex "$accent")" TUI_GREEN="$(_tui_hex green)"
        TUI_MUTED="$(_tui_hex overlay1)" TUI_TEXT="$(_tui_hex text)"
        TUI_SYM_CUR="❯" TUI_SYM_OPEN="▾" TUI_SYM_SHUT="▸" TUI_SYM_ON="[✓]" TUI_SYM_OFF="[ ]"
        TUI_SYM_SOME="[–]" TUI_SYM_PICK="●" TUI_SYM_NOPICK="○" TUI_SYM_LINE="─" TUI_SYM_STAR="★"
        TUI_SYM_SWATCH="██"
    fi
}

# _tui_hex NAME: truecolor foreground escape for a Catppuccin Mocha colour (theme/palette.conf).
_tui_hex() {
    local hex
    hex="$(sed -n "s/^$1=//p" "${NUSKU_ROOT:-.}/theme/palette.conf" 2>/dev/null | head -n1)"
    [ -n "$hex" ] || { printf '%s' $'\e[0m'; return 0; }
    printf '\e[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# tui_swatch NAME: a coloured block for an accent (nothing on the text console).
tui_swatch() {
    [ "$TUI_ASCII" = 1 ] && return 0
    printf '%s%s%s ' "$(_tui_hex "$1")" "$TUI_SYM_SWATCH" "$TUI_RESET"
}

# --- Terminal ---------------------------------------------------------------------------

# tui_open [ACCENT]: take over the terminal (alternate screen, hidden cursor, no echo). Nests:
# a screen opened from another one shares its terminal until the outer one closes.
tui_open() {
    _tui_style "${1:-blue}"
    _TUI_DEPTH=$((_TUI_DEPTH + 1))
    [ "$_TUI_DEPTH" -eq 1 ] || return 0
    exec {_TUI_IN}<"${NUSKU_TUI_IN:-/dev/tty}" {_TUI_OUT}>"${NUSKU_TUI_OUT:-/dev/tty}"
    _TUI_STTY=""
    if [ -t "$_TUI_IN" ]; then
        _TUI_STTY="$(stty -g <&"$_TUI_IN")"
        stty -echo -icanon <&"$_TUI_IN"
    fi
    printf '\e[?1049h\e[?25l' >&"$_TUI_OUT"
    trap '_tui_interrupt' INT
}

# tui_close: give the terminal back as it was.
tui_close() {
    [ "$_TUI_DEPTH" -le 1 ] || { _TUI_DEPTH=$((_TUI_DEPTH - 1)); return 0; }
    _TUI_DEPTH=0
    trap - INT
    [ -n "$_TUI_OUT" ] || return 0
    printf '\e[?25h\e[?1049l' >&"$_TUI_OUT"
    if [ -n "$_TUI_STTY" ]; then
        stty "$_TUI_STTY" <&"$_TUI_IN" || true
    fi
    exec {_TUI_IN}<&- {_TUI_OUT}>&-
    _TUI_IN="" _TUI_OUT="" _TUI_STTY="" _TUI_DEPTH=0
}

_tui_interrupt() {
    _TUI_DEPTH=1
    tui_close
    die "Cancelled"
}

# _tui_size: TUI_ROWS and TUI_COLS of the terminal (NUSKU_TUI_ROWS/COLS when it is not one).
_tui_size() {
    local size=""
    if [ -t "$_TUI_OUT" ]; then
        size="$(stty size <&"$_TUI_OUT" 2>/dev/null)" || size=""
    fi
    if [ -n "$size" ]; then
        TUI_ROWS="${size% *}" TUI_COLS="${size#* }"
    else
        TUI_ROWS="${NUSKU_TUI_ROWS:-30}" TUI_COLS="${NUSKU_TUI_COLS:-100}"
    fi
}

# tui_key: read one key into TUI_KEY: up down left right home end pgup pgdn space enter esc
# ctrl-c eof, or char:X. Running out of input (eof) counts as Esc for the callers.
tui_key() {
    local c="" n1="" n2="" n3=""
    if [ -n "$_TUI_PENDING" ]; then
        c="$_TUI_PENDING"
        _TUI_PENDING=""
    elif ! IFS= read -rsn1 -u "$_TUI_IN" c; then
        TUI_KEY=eof
        return 0
    fi
    case "$c" in
        $'\e')
            if ! IFS= read -rsn1 -t 0.05 -u "$_TUI_IN" n1; then
                TUI_KEY=esc
                return 0
            fi
            case "$n1" in
                '[' | O)
                    IFS= read -rsn1 -t 0.05 -u "$_TUI_IN" n2 || n2=""
                    case "$n2" in
                        A) TUI_KEY=up ;;
                        B) TUI_KEY=down ;;
                        C) TUI_KEY=right ;;
                        D) TUI_KEY=left ;;
                        H) TUI_KEY=home ;;
                        F) TUI_KEY=end ;;
                        [0-9])
                            # ESC [ n ~ : 1/7 Home, 4/8 End, 5 PgUp, 6 PgDn (others ignored)
                            IFS= read -rsn1 -t 0.05 -u "$_TUI_IN" n3 || n3=""
                            case "$n2" in
                                1 | 7) TUI_KEY=home ;;
                                4 | 8) TUI_KEY=end ;;
                                5) TUI_KEY=pgup ;;
                                6) TUI_KEY=pgdn ;;
                                *) TUI_KEY=none ;;
                            esac
                            ;;
                        *) TUI_KEY=none ;;
                    esac
                    ;;
                *)
                    # Esc, then another key typed straight after it: keep that key for next time.
                    TUI_KEY=esc
                    _TUI_PENDING="${n1:-$'\n'}"
                    ;;
            esac
            ;;
        '' | $'\r' | $'\n') TUI_KEY=enter ;;
        ' ') TUI_KEY=space ;;
        $'\x03') TUI_KEY=ctrl-c ;;
        k) TUI_KEY=up ;;
        j) TUI_KEY=down ;;
        h) TUI_KEY=left ;;
        l) TUI_KEY=right ;;
        *) TUI_KEY="char:$c" ;;
    esac
}

# --- Drawing ----------------------------------------------------------------------------

# _tui_frame TITLE SUBTITLE HINT CURSOR LINE...: draw a screen. LINE is pre-formatted; CURSOR
# is the index of the highlighted line (-1 for none). Long lists scroll to keep it in view.
_tui_frame() {
    local title="$1" sub="$2" hint="$3" cur="$4" i top=0 room out=""
    shift 4
    local -a lines=("$@")
    _tui_size
    room=$((TUI_ROWS - 6))
    [ "$room" -ge 3 ] || room=3
    if [ "$cur" -ge "$room" ]; then
        top=$((cur - room + 1))
    fi
    out+=$'\e[H'"$TUI_ACCENT  $title$TUI_RESET"$'\e[K\n'
    out+="$TUI_MUTED  $sub$TUI_RESET"$'\e[K\n\e[K\n'
    for ((i = top; i < ${#lines[@]} && i < top + room; i++)); do
        if [ "$i" -eq "$cur" ]; then
            out+="$TUI_ACCENT$TUI_SYM_CUR$TUI_RESET ${lines[$i]}"$'\e[K\n'
        else
            out+="  ${lines[$i]}"$'\e[K\n'
        fi
    done
    out+=$'\e[K\n'"$TUI_MUTED  $hint$TUI_RESET"$'\e[J'
    printf '%s' "$out" >&"$_TUI_OUT"
}

# --- Single choice ----------------------------------------------------------------------

# tui_choose TITLE SUBTITLE CURRENT_INDEX LABEL...: pick one. Sets TUI_CHOICE and returns 0;
# Esc returns 1 and changes nothing. The current choice is marked.
tui_choose() {
    local title="$1" sub="$2" current="$3" cur i n
    shift 3
    local -a labels=("$@") lines=()
    n=${#labels[@]}
    cur="$current"
    [ "$cur" -ge 0 ] && [ "$cur" -lt "$n" ] || cur=0
    local hint="up/down move · enter picks · esc goes back"
    [ "$TUI_ASCII" = 1 ] || hint="↑↓ move · enter picks · esc goes back"
    while :; do
        lines=()
        for ((i = 0; i < n; i++)); do
            if [ "$i" -eq "$current" ]; then
                lines+=("$TUI_ACCENT$TUI_SYM_PICK$TUI_RESET ${labels[$i]}")
            else
                lines+=("$TUI_MUTED$TUI_SYM_NOPICK$TUI_RESET ${labels[$i]}")
            fi
        done
        _tui_frame "$title" "$sub" "$hint" "$cur" "${lines[@]}"
        tui_key
        case "$TUI_KEY" in
            up) [ "$cur" -gt 0 ] && cur=$((cur - 1)) || cur=$((n - 1)) ;;
            down) [ "$cur" -lt $((n - 1)) ] && cur=$((cur + 1)) || cur=0 ;;
            home | pgup) cur=0 ;;
            end | pgdn) cur=$((n - 1)) ;;
            enter | space | right)
                TUI_CHOICE="$cur"
                return 0
                ;;
            esc | eof | left) return 1 ;;
            ctrl-c) _tui_interrupt ;;
        esac
    done
}

# --- Menu of settings -------------------------------------------------------------------

# tui_menu TITLE SUBTITLE HINT CURSOR LINE...: a plain list; a LINE of "-" is a divider that
# the cursor skips. Sets TUI_CHOICE to the picked index and returns 0; Esc returns 1.
tui_menu() {
    local title="$1" sub="$2" hint="$3" cur="$4" i n
    shift 4
    local -a lines=("$@") shown=()
    local rule=""
    for ((i = 0; i < 44; i++)); do rule+="$TUI_SYM_LINE"; done
    n=${#lines[@]}
    for ((i = 0; i < n; i++)); do
        if [ "${lines[$i]}" = "-" ]; then
            shown+=("$TUI_MUTED$rule$TUI_RESET")
        else
            shown+=("${lines[$i]}")
        fi
    done
    _tui_step() { # _tui_step DIR: move the cursor one selectable line in DIR (+1/-1)
        local next="$cur" k
        for ((k = 0; k < n; k++)); do
            next=$(((next + $1 + n) % n))
            if [ "${lines[$next]}" != "-" ]; then
                cur="$next"
                return 0
            fi
        done
    }
    while :; do
        _tui_frame "$title" "$sub" "$hint" "$cur" "${shown[@]}"
        tui_key
        case "$TUI_KEY" in
            up) _tui_step -1 ;;
            down) _tui_step 1 ;;
            enter | space | right)
                TUI_CHOICE="$cur"
                return 0
                ;;
            esc | eof) return 1 ;;
            ctrl-c) _tui_interrupt ;;
        esac
    done
}

# --- Tree of checkboxes -----------------------------------------------------------------
# Rows are set by the caller in these arrays (one entry per row, groups before their items):
#   TUI_T_KIND[i]   g (group) or i (item)
#   TUI_T_LABEL[i]  text
#   TUI_T_PARENT[i] for an item, the row index of its group
#   TUI_T_ON[i]     for an item, 1 when ticked
#   TUI_T_OPEN[i]   for a group, 1 when unfolded
TUI_T_KIND=() TUI_T_LABEL=() TUI_T_PARENT=() TUI_T_ON=() TUI_T_OPEN=()

# _tui_group_count G: "ticked/total" for group row G.
_tui_group_count() {
    local i on=0 all=0
    for i in "${!TUI_T_KIND[@]}"; do
        if [ "${TUI_T_KIND[$i]}" = i ] && [ "${TUI_T_PARENT[$i]}" = "$1" ]; then
            all=$((all + 1))
            [ "${TUI_T_ON[$i]}" = 1 ] && on=$((on + 1))
        fi
    done
    printf '%s/%s' "$on" "$all"
}

# _tui_group_set G VALUE: tick (1) or untick (0) every item of group row G.
_tui_group_set() {
    local i
    for i in "${!TUI_T_KIND[@]}"; do
        if [ "${TUI_T_KIND[$i]}" = i ] && [ "${TUI_T_PARENT[$i]}" = "$1" ]; then
            TUI_T_ON[i]="$2"
        fi
    done
}

# tui_tree TITLE SUBTITLE: tick items in folding groups, then pick Done. Returns 0 on Done
# (the arrays hold the result) and 1 on Esc (the caller keeps what it had).
tui_tree() {
    local title="$1" sub="$2" i n cur=0 pos k count g mark width=34
    n=${#TUI_T_KIND[@]}
    local -a vis=() lines=()
    local hint="up/down move · space ticks · enter or right opens a group · left closes · esc cancels"
    [ "$TUI_ASCII" = 1 ] || hint="↑↓ move · space ticks · enter/→ opens a group · ← closes · esc cancels"
    while :; do
        # Visible rows: every group, items of open groups, then Done (index n).
        vis=() lines=()
        for ((i = 0; i < n; i++)); do
            if [ "${TUI_T_KIND[$i]}" = g ]; then
                vis+=("$i")
                count="$(_tui_group_count "$i")"
                if [ "${count%/*}" = 0 ]; then
                    mark="$TUI_SYM_OFF"
                elif [ "${count%/*}" = "${count#*/}" ]; then
                    mark="$TUI_GREEN$TUI_SYM_ON$TUI_RESET"
                else
                    mark="$TUI_GREEN$TUI_SYM_SOME$TUI_RESET"
                fi
                if [ "${TUI_T_OPEN[$i]}" = 1 ]; then g="$TUI_SYM_OPEN"; else g="$TUI_SYM_SHUT"; fi
                lines+=("$(printf '%s %s %s%-*s%s %s%s%s' "$g" "$mark" "$TUI_BOLD" "$width" "${TUI_T_LABEL[$i]}" "$TUI_RESET" "$TUI_MUTED" "$count" "$TUI_RESET")")
            elif [ "${TUI_T_OPEN[${TUI_T_PARENT[$i]}]}" = 1 ]; then
                vis+=("$i")
                if [ "${TUI_T_ON[$i]}" = 1 ]; then
                    lines+=("      $TUI_GREEN$TUI_SYM_ON$TUI_RESET ${TUI_T_LABEL[$i]}")
                else
                    lines+=("      $TUI_MUTED$TUI_SYM_OFF$TUI_RESET ${TUI_T_LABEL[$i]}")
                fi
            fi
        done
        vis+=("$n")
        lines+=("" "$TUI_ACCENT  Done$TUI_RESET")
        # Where the cursor row is in the visible list (Done sits after a blank line).
        pos=0
        for k in "${!vis[@]}"; do
            [ "${vis[$k]}" = "$cur" ] && pos="$k"
        done
        local drawpos="$pos"
        [ "$cur" -eq "$n" ] && drawpos=$((${#lines[@]} - 1))
        _tui_frame "$title" "$sub" "$hint" "$drawpos" "${lines[@]}"
        tui_key
        case "$TUI_KEY" in
            up) [ "$pos" -gt 0 ] && cur="${vis[$((pos - 1))]}" || cur="$n" ;;
            down) [ "$pos" -lt $((${#vis[@]} - 1)) ] && cur="${vis[$((pos + 1))]}" || cur="${vis[0]}" ;;
            home) cur="${vis[0]}" ;;
            end) cur="$n" ;;
            pgup) k=$((pos - 10)); [ "$k" -ge 0 ] || k=0; cur="${vis[$k]}" ;;
            pgdn) k=$((pos + 10)); [ "$k" -lt "${#vis[@]}" ] || k=$((${#vis[@]} - 1)); cur="${vis[$k]}" ;;
            esc | eof) return 1 ;;
            ctrl-c) _tui_interrupt ;;
            space | enter | right | left)
                if [ "$cur" -eq "$n" ]; then
                    case "$TUI_KEY" in space | enter) return 0 ;; esac
                elif [ "${TUI_T_KIND[$cur]}" = g ]; then
                    case "$TUI_KEY" in
                        space)
                            count="$(_tui_group_count "$cur")"
                            if [ "${count%/*}" = "${count#*/}" ]; then
                                _tui_group_set "$cur" 0
                            else
                                _tui_group_set "$cur" 1
                            fi
                            ;;
                        enter) if [ "${TUI_T_OPEN[$cur]}" = 1 ]; then TUI_T_OPEN[cur]=0; else TUI_T_OPEN[cur]=1; fi ;;
                        right) TUI_T_OPEN[cur]=1 ;;
                        left) TUI_T_OPEN[cur]=0 ;;
                    esac
                else
                    case "$TUI_KEY" in
                        space | enter) if [ "${TUI_T_ON[$cur]}" = 1 ]; then TUI_T_ON[cur]=0; else TUI_T_ON[cur]=1; fi ;;
                        left)
                            cur="${TUI_T_PARENT[$cur]}"
                            TUI_T_OPEN[cur]=0
                            ;;
                    esac
                fi
                ;;
        esac
    done
}
