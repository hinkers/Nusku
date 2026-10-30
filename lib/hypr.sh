#!/usr/bin/env bash
# Hyprland per-machine files and the move from hyprlang (.conf) to Lua. Sourced, not executed.
# Needs lib/log.sh.

# hypr_write_local_lua FILE: create the per-machine override file (loaded last by
# ~/.config/hypr/hyprland.lua) with a commented example, unless it already exists.
hypr_write_local_lua() {
    local file="${1:?hypr_write_local_lua needs a file}"
    [ -e "$file" ] && return 0
    mkdir -p "$(dirname "$file")"
    cat >"$file" <<'EOF'
-- Your own Hyprland settings (Lua). Nusku never overwrites this file.
-- It is loaded last by ~/.config/hypr/hyprland.lua, so anything here wins.
-- Syntax: https://wiki.hypr.land/Configuring/  Examples:
--   hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
--   hl.config({ input = { kb_layout = "us,de", kb_options = "grp:alt_shift_toggle" } })
--   hl.bind("SUPER + D", hl.dsp.exec_cmd("discord"))
EOF
    log_info "Created $file"
}

# hypr_migrate_legacy NUSKU_CONFIG_DIR: clean up after a hyprlang-era (Stage 1) install.
# The generated gpu.conf and theme/hypr-*.conf are Nusku's own and are removed.
# local.conf is the user's: it is kept, with a warning if it holds settings.
hypr_migrate_legacy() {
    local dir="${1:?hypr_migrate_legacy needs the Nusku config dir}" f
    for f in "$dir/gpu.conf" "$dir/theme/hypr-colors.conf" "$dir/theme/hypr-cursor.conf"; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            rm -f "$f"
            log_info "Removed $f (Hyprland now reads Lua)"
        fi
    done
    f="$dir/local.conf"
    if [ -f "$f" ] && grep -qEv '^[[:space:]]*(#|$)' "$f"; then
        log_warn "$f is no longer read: Hyprland now uses Lua. Move your overrides into $dir/local.lua (see https://wiki.hypr.land/Configuring/)."
    fi
    return 0
}
