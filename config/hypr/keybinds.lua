-- Nusku - keybinds. mod is SUPER. Flags: repeating = held key repeats (old binde),
-- locked = also works on the lock screen (old bindl), mouse = drag binds (old bindm).

local mod = "SUPER"
local dsp = hl.dsp

local function key(...)
    return table.concat({ ... }, " + ")
end

-- --- Apps -------------------------------------------------------------
hl.bind(key(mod, "Return"), dsp.exec_cmd("kitty"))
hl.bind(key(mod, "Space"),  dsp.exec_cmd("rofi -show drun"))
hl.bind(key(mod, "E"),      dsp.exec_cmd("thunar"))
hl.bind(key(mod, "V"),      dsp.exec_cmd("~/.local/bin/nusku-menu-clipboard"))
hl.bind(key(mod, "W"),      dsp.exec_cmd("~/.local/bin/nusku-menu-wallpaper"))
hl.bind(key(mod, "Escape"), dsp.exec_cmd("~/.local/bin/nusku-menu-power"))
hl.bind(key(mod, "N"),      dsp.exec_cmd("swaync-client -t -sw"))

-- --- Session ----------------------------------------------------------
hl.bind(key(mod, "L"), dsp.exec_cmd("hyprlock"))

-- --- Window management ------------------------------------------------
hl.bind(key(mod, "Q"), dsp.window.close())
hl.bind(key(mod, "F"), dsp.window.fullscreen())
hl.bind(key(mod, "T"), dsp.window.float({ action = "toggle" }))
hl.bind(key(mod, "P"), dsp.window.pseudo())
hl.bind(key(mod, "J"), dsp.layout("togglesplit"))

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    -- Focus
    hl.bind(key(mod, dir), dsp.focus({ direction = dir }))
    -- Move window
    hl.bind(key(mod, "SHIFT", dir), dsp.window.move({ direction = dir }))
end

-- Resize (repeats while held)
hl.bind(key(mod, "CTRL", "left"),  dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(key(mod, "CTRL", "right"), dsp.window.resize({ x = 40, y = 0, relative = true }),  { repeating = true })
hl.bind(key(mod, "CTRL", "up"),    dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(key(mod, "CTRL", "down"),  dsp.window.resize({ x = 0, y = 40, relative = true }),  { repeating = true })

-- Mouse: drag with left = move, right = resize
hl.bind(key(mod, "mouse:272"), dsp.window.drag(),   { mouse = true })
hl.bind(key(mod, "mouse:273"), dsp.window.resize(), { mouse = true })

-- --- Workspaces -------------------------------------------------------
for i = 1, 10 do
    local k = tostring(i % 10) -- workspace 10 is on key 0
    hl.bind(key(mod, k), dsp.focus({ workspace = i }))
    hl.bind(key(mod, "SHIFT", k), dsp.window.move({ workspace = i }))
end

hl.bind(key(mod, "mouse_down"), dsp.focus({ workspace = "e+1" }))
hl.bind(key(mod, "mouse_up"),   dsp.focus({ workspace = "e-1" }))

-- --- Screenshots (hyprshot: clipboard + ~/Pictures/Screenshots) ---------
hl.bind("Print",              dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots"))
hl.bind(key("SHIFT", "Print"), dsp.exec_cmd("hyprshot -m window -o ~/Pictures/Screenshots"))
hl.bind(key("CTRL", "Print"),  dsp.exec_cmd("hyprshot -m output -o ~/Pictures/Screenshots"))

-- --- Media keys (work when locked, volume/brightness repeat when held) ---
local held = { locked = true, repeating = true }
local locked = { locked = true }
hl.bind("XF86AudioRaiseVolume",  dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), held)
hl.bind("XF86AudioLowerVolume",  dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"), held)
hl.bind("XF86AudioMute",         dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)
hl.bind("XF86AudioMicMute",      dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
hl.bind("XF86MonBrightnessUp",   dsp.exec_cmd("brightnessctl set 5%+"), held)
hl.bind("XF86MonBrightnessDown", dsp.exec_cmd("brightnessctl set 5%-"), held)
hl.bind("XF86AudioPlay",         dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPause",        dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioNext",         dsp.exec_cmd("playerctl next"), locked)
hl.bind("XF86AudioPrev",         dsp.exec_cmd("playerctl previous"), locked)
