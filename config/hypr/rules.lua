-- Nusku - window rules (Lua: hl.window_rule({ name, match = { prop = regex }, effect = value })).

-- Utility windows float.
hl.window_rule({
    name = "nusku-float-pavucontrol",
    match = { class = [[^(org\.pulseaudio\.pavucontrol|pavucontrol)$]] },
    float = true,
})
hl.window_rule({
    name = "nusku-float-blueman",
    match = { class = [[^(\.blueman-manager-wrapped|blueman-manager)$]] },
    float = true,
})
hl.window_rule({
    name = "nusku-float-nm-connection-editor",
    match = { class = [[^(nm-connection-editor)$]] },
    float = true,
})
-- Network picker (waybar network click): nmtui in a floating kitty.
hl.window_rule({
    name = "nusku-float-nmtui",
    match = { class = [[^(nusku-nmtui)$]] },
    float = true,
    size = "720 520",
    center = true,
})
-- GNOME Calendar opens from the clock, so it floats just under the bar, centred.
hl.window_rule({
    name = "nusku-float-calendar",
    match = { class = [[^(org\.gnome\.Calendar)$]] },
    float = true,
    size = "760 560",
    move = "((monitor_w*0.5)-(window_w*0.5)) 46",
})
-- File chooser portal dialogs.
hl.window_rule({
    name = "nusku-float-file-chooser",
    match = { class = [[^(xdg-desktop-portal-gtk)$]] },
    float = true,
})

-- Keep the screen awake while anything is fullscreen (video, games).
hl.window_rule({
    name = "nusku-idle-inhibit-fullscreen",
    match = { class = ".*" },
    idle_inhibit = "fullscreen",
})
