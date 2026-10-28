#!/usr/bin/env bash
# Answers file: parsed line by line (never sourced), held in NUSKU_ANSWERS. Sourced, not executed.
# Needs lib/log.sh (die, log_warn).

if ! declare -p NUSKU_ANSWERS >/dev/null 2>&1; then
    declare -gA NUSKU_ANSWERS=()
fi

# The 14 Catppuccin accents; reused by the theme code.
if ! declare -p NUSKU_ACCENTS >/dev/null 2>&1; then
    declare -gra NUSKU_ACCENTS=(rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender)
fi

_NUSKU_ANSWER_KEYS=(GPU NVIDIA_MODULE AUR_HELPER ACCENT APPS LANGS TEST_AUTOLOGIN)

_answers_known_key() {
    local k
    for k in "${_NUSKU_ANSWER_KEYS[@]}"; do
        [ "$k" = "$1" ] && return 0
    done
    return 1
}

answers_get() {
    printf '%s\n' "${NUSKU_ANSWERS[$1]:-}"
}

answers_set() {
    NUSKU_ANSWERS[$1]="$2"
}

# answers_load FILE: KEY=value lines; '#' comments and blank lines skipped; value is taken literally.
answers_load() {
    local file="$1" line key value
    [ -r "$file" ] || die "answers file not readable: $file"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        # trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            '' | '#'*) continue ;;
        esac
        case "$line" in
            *=*) ;;
            *)
                log_warn "answers: ignoring malformed line: $line"
                continue
                ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        if ! _answers_known_key "$key"; then
            log_warn "answers: ignoring unknown key: $key"
            continue
        fi
        NUSKU_ANSWERS[$key]="$value"
    done <"$file"
}

answers_save() {
    local file="$1" key
    mkdir -p "$(dirname "$file")"
    {
        printf '# Nusku answers\n'
        for key in "${_NUSKU_ANSWER_KEYS[@]}"; do
            if [ -n "${NUSKU_ANSWERS[$key]+x}" ]; then
                printf '%s=%s\n' "$key" "${NUSKU_ANSWERS[$key]}"
            fi
        done
    } >"$file"
}

# _answers_require_in KEY ALLOWED...: value of KEY must be one of ALLOWED.
_answers_require_in() {
    local key="$1" val a
    shift
    val="${NUSKU_ANSWERS[$key]:-}"
    [ -n "$val" ] || die "answers: $key is required; allowed values: $*"
    for a in "$@"; do
        [ "$a" = "$val" ] && return 0
    done
    die "answers: invalid $key='$val'; allowed values: $*"
}

answers_validate() {
    _answers_require_in GPU amd intel nvidia hybrid-intel hybrid-amd vm
    case "${NUSKU_ANSWERS[GPU]}" in
        nvidia | hybrid-*) _answers_require_in NVIDIA_MODULE proprietary open ;;
        *)
            if [ -n "${NUSKU_ANSWERS[NVIDIA_MODULE]:-}" ]; then
                _answers_require_in NVIDIA_MODULE proprietary open
            fi
            ;;
    esac
    _answers_require_in AUR_HELPER paru yay
    _answers_require_in ACCENT "${NUSKU_ACCENTS[@]}"
    if declare -F apps_validate_answers >/dev/null; then
        apps_validate_answers
    fi
    if [ -n "${NUSKU_ANSWERS[TEST_AUTOLOGIN]:-}" ]; then
        _answers_require_in TEST_AUTOLOGIN 0 1
    fi
}
