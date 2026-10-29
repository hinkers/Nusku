-- Nusku - session autostart (runs once when Hyprland starts, not on config reloads).

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("~/.local/bin/nusku-wallpaper restore")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- The ArtCraft Launcher's own autostart entry (its "start at login" setting): use its Exec only.
    local f = io.open((os.getenv("HOME") or "") .. "/.config/autostart/ai.storyteller.artcraft-launcher.desktop", "r")
    if f then
        local text = f:read("*a")
        f:close()
        local exec = ("\n" .. text):match("\nExec=([^\n]+)")
        if exec then
            hl.exec_cmd(exec)
        end
    end
end)
