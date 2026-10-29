-- Nusku - where the installer's generated files live (~/.config/nusku by default).

local config_home = os.getenv("XDG_CONFIG_HOME")
if config_home == nil or config_home == "" then
    config_home = os.getenv("HOME") .. "/.config"
end

return {
    -- the XDG config home itself (autostart entries live in <config>/autostart)
    config = config_home,
    -- gpu.lua (generated) and local.lua (yours)
    nusku = config_home .. "/nusku",
    -- hypr-colors.lua and hypr-cursor.lua, rendered from theme/palette.conf
    theme = config_home .. "/nusku/theme",
}
