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
