#!/usr/bin/env bash
# gum-backed prompts that short-circuit on stored answers. Sourced, not executed.
# Needs lib/log.sh (die) and lib/answers.sh. Call these directly (not inside
# $(...)) when you need the answer stored in the caller's NUSKU_ANSWERS; the
# value is also printed on stdout.

# _ui_stored KEY: if answered (or non-interactive), print value and return 0.
_ui_stored() {
    local key="$1"
    if [ -n "${NUSKU_ANSWERS[$key]+x}" ]; then
        printf '%s\n' "${NUSKU_ANSWERS[$key]}"
        return 0
    fi
    if [ "${NUSKU_NONINTERACTIVE:-0}" = "1" ]; then
        die "answers file missing $key"
    fi
    return 1
}

# ui_choose KEY PROMPT DEFAULT OPTION...
ui_choose() {
    local key="$1" prompt="$2" default="$3" choice
    shift 3
    _ui_stored "$key" && return 0
    choice="$(gum choose --header "$prompt" --selected "$default" "$@")" || die "no selection made for $key"
    answers_set "$key" "$choice"
    printf '%s\n' "$choice"
}

# ui_confirm PROMPT: 0 = yes, 1 = no. Non-interactive assumes yes.
ui_confirm() {
    if [ "${NUSKU_NONINTERACTIVE:-0}" = "1" ]; then
        return 0
    fi
    gum confirm "$1"
}

# ui_checklist KEY PROMPT PRESELECTED_CSV OPTION...: stores a space-separated list.
ui_checklist() {
    local key="$1" prompt="$2" pre="$3" out
    shift 3
    _ui_stored "$key" && return 0
    out="$(gum choose --no-limit --header "$prompt" --selected "$pre" "$@")" || out=""
    out="$(printf '%s' "$out" | tr '\n' ' ')"
    out="${out% }"
    answers_set "$key" "$out"
    printf '%s\n' "$out"
}
