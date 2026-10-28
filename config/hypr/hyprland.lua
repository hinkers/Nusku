-- Nusku - Hyprland entry point. Only loads the split modules; edit those instead.
-- Each require() runs in its own scope, so an error in one module does not stop the others.
-- Order matters: per-machine overrides come last (they win).

local paths = require("paths")

require("env")
require("monitors")
require("input")
require("looks")
require("animations")
require("keybinds")
require("rules")
require("autostart")

-- require() of a missing file is a hard error, so optional files are checked first.
local function require_if_present(module)
    local file = io.open(module .. ".lua", "r")
    if file == nil then
        return
    end
    file:close()
    require(module)
end

-- Written by the installer: GPU-specific env vars / cursor and monitor workarounds.
require_if_present(paths.nusku .. "/gpu")
-- Per-machine overrides (monitors, input, extra binds, ...). Loaded last.
require_if_present(paths.nusku .. "/local")
