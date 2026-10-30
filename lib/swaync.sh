# Nusku - swaync quick-settings panel: config.json is written per machine from a template.
# Needs lib/log.sh and jq.
#
# Per machine: the brightness slider needs a backlight device (laptops), and the power-mode
# buttons only list the profiles power-profiles-daemon offers here.

# swaync_backlight: the first backlight device name, or nothing.
swaync_backlight() {
    local d
    for d in "${NUSKU_BACKLIGHT_DIR:-/sys/class/backlight}"/*; do
        [ -e "$d" ] || continue
        printf '%s\n' "${d##*/}"
        return 0
    done
    return 1
}

# swaync_power_profiles: the profiles this machine has, space separated (all three if unknown).
swaync_power_profiles() {
    if [ -n "${NUSKU_POWER_PROFILES+x}" ]; then
        printf '%s\n' "$NUSKU_POWER_PROFILES"
        return 0
    fi
    local list
    if list="$(powerprofilesctl list 2>/dev/null)" && [ -n "$list" ]; then
        sed -n 's/^[* ] *\([a-z-]*\):$/\1/p' <<<"$list" | tr '\n' ' '
        echo
    else
        echo "power-saver balanced performance"
    fi
}

# swaync_write_config TEMPLATE DEST: write the machine's panel config.
swaync_write_config() {
    local template="$1" dest="$2" backlight profiles
    backlight="$(swaync_backlight)" || backlight=""
    profiles="$(swaync_power_profiles)"
    mkdir -p "$(dirname "$dest")"
    jq --arg bl "$backlight" --arg profiles " $profiles " '
        (if $bl == "" then
            .widgets -= ["backlight"] | del(."widget-config".backlight)
         else
            ."widget-config".backlight.device = $bl
         end)
        | ."widget-config"."buttons-grid#power".actions |= map(select(
            (.command | split(" ") | last) as $p | $profiles | contains(" " + $p + " ")))
        | if (."widget-config"."buttons-grid#power".actions | length) < 2 then
            .widgets -= ["buttons-grid#power"] | del(."widget-config"."buttons-grid#power")
          else . end
    ' "$template" >"$dest.tmp" && mv -f "$dest.tmp" "$dest" || {
        rm -f "$dest.tmp"
        log_warn "Could not write $dest"
        return 1
    }
    log_info "Quick settings: ${backlight:-no} backlight; power modes: ${profiles% }"
}
