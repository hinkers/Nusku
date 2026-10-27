#!/usr/bin/env bash
# GRUB and mkinitcpio file editing helpers. Sourced, not executed.
# These functions edit FILE in place (no sudo; callers edit a temp copy for /etc files)
# and return 0 if the file changed, 1 if it already had everything, 2 if FILE is unreadable.

# grub_add_params FILE PARAM...: add params to GRUB_CMDLINE_LINUX_DEFAULT, keeping existing ones and quoting.
grub_add_params() {
    local file="${1:-}"
    shift || true
    [ -r "$file" ] || return 2
    local line cur quote='"' p new changed=0
    line="$(grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file" || true)"
    if [ -z "$line" ]; then
        cur=""
    else
        cur="${line#GRUB_CMDLINE_LINUX_DEFAULT=}"
        case "${cur:0:1}" in
            "'")
                quote="'"
                cur="${cur#\'}"
                cur="${cur%\'}"
                ;;
            '"')
                cur="${cur#\"}"
                cur="${cur%\"}"
                ;;
        esac
    fi
    new="$cur"
    for p in "$@"; do
        case " $new " in
            *" $p "*) ;;
            *)
                new="${new:+$new }$p"
                changed=1
                ;;
        esac
    done
    [ "$changed" -eq 1 ] || return 1
    local repl="GRUB_CMDLINE_LINUX_DEFAULT=${quote}${new}${quote}" tmp
    tmp="$(mktemp)"
    if [ -z "$line" ]; then
        {
            cat "$file"
            printf '%s\n' "$repl"
        } >"$tmp"
    else
        awk -v repl="$repl" '!done && /^GRUB_CMDLINE_LINUX_DEFAULT=/ { print repl; done=1; next } { print }' "$file" >"$tmp"
    fi
    cat "$tmp" >"$file"
    rm -f "$tmp"
    return 0
}

# mkinit_add_modules FILE MOD...: add modules to MODULES=(...) in a mkinitcpio.conf.
mkinit_add_modules() {
    local file="${1:-}"
    shift || true
    [ -r "$file" ] || return 2
    local line cur m new changed=0 tmp _mods=()
    line="$(grep -m1 '^MODULES=(' "$file" || true)"
    cur=""
    if [ -n "$line" ]; then
        cur="${line#MODULES=(}"
        cur="${cur%%)*}"
    fi
    read -ra _mods <<<"$cur"
    new="${_mods[*]}"
    for m in "$@"; do
        case " $new " in
            *" $m "*) ;;
            *)
                new="${new:+$new }$m"
                changed=1
                ;;
        esac
    done
    [ "$changed" -eq 1 ] || return 1
    tmp="$(mktemp)"
    if [ -z "$line" ]; then
        {
            cat "$file"
            printf 'MODULES=(%s)\n' "$new"
        } >"$tmp"
    else
        awk -v repl="MODULES=($new)" '!done && /^MODULES=\(/ { print repl; done=1; next } { print }' "$file" >"$tmp"
    fi
    cat "$tmp" >"$file"
    rm -f "$tmp"
    return 0
}

# mkinit_remove_hook FILE HOOK: drop HOOK from HOOKS=(...) in a mkinitcpio.conf
# (1 if it is not there or there is no HOOKS line).
mkinit_remove_hook() {
    local file="${1:-}" hook="${2:-}"
    [ -r "$file" ] || return 2
    local line cur h kept=() changed=0 tmp _hooks=()
    line="$(grep -m1 '^HOOKS=(' "$file" || true)"
    [ -n "$line" ] || return 1
    cur="${line#HOOKS=(}"
    cur="${cur%%)*}"
    read -ra _hooks <<<"$cur"
    for h in "${_hooks[@]}"; do
        if [ "$h" = "$hook" ]; then
            changed=1
        else
            kept+=("$h")
        fi
    done
    [ "$changed" -eq 1 ] || return 1
    tmp="$(mktemp)"
    awk -v repl="HOOKS=(${kept[*]})" '!done && /^HOOKS=\(/ { print repl; done=1; next } { print }' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
    return 0
}
