-- Nusku - session autostart (runs once when Hyprland starts, not on config reloads).

local paths = require("paths")

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("~/.local/bin/nusku-wallpaper restore")
    hl.exec_cmd("waybar")
    -- Through systemd: D-Bus activation also starts this unit, so a bare "swaync" would race it.
    hl.exec_cmd("systemctl --user start swaync")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- The ArtCraft Launcher's own autostart entry (its "start at login" setting): use its Exec only.
    local f = io.open(paths.config .. "/autostart/ai.storyteller.artcraft-launcher.desktop", "r")
    if f then
        local text = f:read("*a")
        f:close()
        local body = "\n" .. text
        local exec = body:match("\nExec=([^\n]+)")
        local disabled = body:find("\nHidden=true", 1, true) or body:find("\nX-GNOME-Autostart-enabled=false", 1, true)
        if exec and not disabled then
            hl.exec_cmd(exec)
        end
    end
end)
