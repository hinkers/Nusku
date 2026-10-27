#!/usr/bin/env bash
# Palette loading and template rendering. Sourced, not executed.
# Needs lib/log.sh (die) and lib/answers.sh (answers_get, NUSKU_ACCENTS).
#
# Template syntax: {{name}} hex without '#', {{name_rgb}} "r, g, b",
# {{accent}} / {{accent_rgb}} for the chosen accent, {{accent_name}} its name.

if ! declare -p NUSKU_COLORS >/dev/null 2>&1; then
    declare -gA NUSKU_COLORS=()
fi
NUSKU_ACCENT_NAME=""

# theme_load PALETTE_FILE ACCENT: fill NUSKU_COLORS from name=hex lines and add 'accent'.
theme_load() {
    local file="$1" accent="$2" line name hex a ok=0
    [ -r "$file" ] || die "palette not readable: $file"
    for a in "${NUSKU_ACCENTS[@]}"; do
        [ "$a" = "$accent" ] && ok=1
    done
    [ "$ok" -eq 1 ] || die "unknown accent '$accent'; allowed: ${NUSKU_ACCENTS[*]}"
    NUSKU_COLORS=()
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in '' | '#'*) continue ;; esac
        name="${line%%=*}"
        hex="${line#*=}"
        [[ "$name" =~ ^[a-z0-9]+$ ]] || die "palette: bad colour name in line: $line"
        [[ "$hex" =~ ^[0-9a-fA-F]{6}$ ]] || die "palette: bad hex for $name: $hex"
        NUSKU_COLORS[$name]="${hex,,}"
    done <"$file"
    [ -n "${NUSKU_COLORS[$accent]:-}" ] || die "palette has no colour for accent '$accent'"
    NUSKU_COLORS[accent]="${NUSKU_COLORS[$accent]}"
    NUSKU_ACCENT_NAME="$accent"
}

_theme_rgb() {
    local h="$1"
    printf '%d, %d, %d' "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"
}

# theme_render TEMPLATE OUT: substitute placeholders; unknown placeholder dies.
theme_render() {
    local tmpl="$1" out="$2" text rest key val
    [ -r "$tmpl" ] || die "template not readable: $tmpl"
    [ -n "$NUSKU_ACCENT_NAME" ] || die "theme_render called before theme_load"
    text="$(
        cat "$tmpl"
        printf x
    )"
    text="${text%x}"
    rest="$text"
    while [[ "$rest" =~ \{\{([A-Za-z0-9_]+)\}\} ]]; do
        key="${BASH_REMATCH[1]}"
        case "$key" in
            accent_name) val="$NUSKU_ACCENT_NAME" ;;
            *_rgb)
                [ -n "${NUSKU_COLORS[${key%_rgb}]:-}" ] || die "unknown placeholder {{$key}} in $tmpl"
                val="$(_theme_rgb "${NUSKU_COLORS[${key%_rgb}]}")"
                ;;
            *)
                [ -n "${NUSKU_COLORS[$key]:-}" ] || die "unknown placeholder {{$key}} in $tmpl"
                val="${NUSKU_COLORS[$key]}"
                ;;
        esac
        text="${text//"{{$key}}"/$val}"
        rest="${rest#*"{{$key}}"}"
    done
    mkdir -p "$(dirname "$out")"
    printf '%s' "$text" >"$out"
}

# _theme_check_home_target PATH: only absent paths or regular files may be overwritten.
_theme_check_home_target() {
    local p="$1"
    if [ -L "$p" ]; then
        die "theme: $p is a symlink; Nusku renders a file there. Remove or move it and re-run."
    elif [ -e "$p" ] && [ ! -f "$p" ]; then
        die "theme: $p exists and is not a regular file; Nusku renders a file there. Remove or move it and re-run."
    fi
}

# theme_render_all REPO_ROOT: top-level templates go to ~/.config/nusku/theme/,
# templates/home/** go to the same relative path under $HOME.
theme_render_all() {
    local root="$1" accent out_dir t rel target
    accent="$(answers_get ACCENT)"
    accent="${accent:-blue}"
    theme_load "$root/theme/palette.conf" "$accent"
    out_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nusku/theme"
    mkdir -p "$out_dir"
    for t in "$root"/theme/templates/*.tmpl; do
        [ -f "$t" ] || continue
        theme_render "$t" "$out_dir/$(basename "${t%.tmpl}")"
    done
    [ -d "$root/theme/templates/home" ] || return 0
    while IFS= read -r -d '' t; do
        rel="${t#"$root"/theme/templates/home/}"
        case "$rel" in
            *.tmpl)
                target="$HOME/${rel%.tmpl}"
                _theme_check_home_target "$target"
                theme_render "$t" "$target"
                ;;
            *)
                target="$HOME/$rel"
                _theme_check_home_target "$target"
                mkdir -p "$(dirname "$target")"
                cp "$t" "$target"
                ;;
        esac
    done < <(find "$root/theme/templates/home" -type f -print0 | sort -z)
}
