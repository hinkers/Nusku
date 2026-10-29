-- Nusku - keybinds. mod is SUPER. Flags: repeating = held key repeats (old binde),
-- locked = also works on the lock screen (old bindl), mouse = drag binds (old bindm),
-- menu = false keeps a bind list-only in the keybind menu.
-- Every bind goes through B.bind with a description; SUPER + / searches them.
-- The dispatcher is written as a Lua expression string so the keybind menu can run it.

local B = require("bindlib")
B.reset()

local mod = "SUPER"

local function key(...)
    return table.concat({ ... }, " + ")
end

-- --- Apps -------------------------------------------------------------
B.bind(key(mod, "Return"), "Open terminal",  'hl.dsp.exec_cmd("kitty")')
B.bind(key(mod, "Space"),  "App launcher",   'hl.dsp.exec_cmd("rofi -show drun")')
B.bind(key(mod, "E"),      "File manager",   'hl.dsp.exec_cmd("thunar")')

-- Yazi alongside Thunar, only when installed (no dead bind otherwise)
do
    local f = io.open("/usr/bin/yazi", "r")
    if f then
        f:close()
        B.bind(key(mod, "SHIFT", "E"), "File manager in the terminal (Yazi)", 'hl.dsp.exec_cmd("kitty -e yazi")')
    end
end

B.bind(key(mod, "V"),      "Clipboard history", 'hl.dsp.exec_cmd("~/.local/bin/nusku-menu-clipboard")')
B.bind(key(mod, "W"),      "Change wallpaper",  'hl.dsp.exec_cmd("~/.local/bin/nusku-menu-wallpaper")')
B.bind(key(mod, "Escape"), "Power menu",        'hl.dsp.exec_cmd("~/.local/bin/nusku-menu-power")')
B.bind(key(mod, "N"),      "Notifications",     'hl.dsp.exec_cmd("swaync-client -t -sw")')
B.bind(key(mod, "slash"),  "Search keybinds",   'hl.dsp.exec_cmd("~/.local/bin/nusku-menu-keybinds")')

-- --- Session ----------------------------------------------------------
B.bind(key(mod, "L"), "Lock screen", 'hl.dsp.exec_cmd("hyprlock")')

-- --- Window management ------------------------------------------------
B.bind(key(mod, "Q"), "Close window",             'hl.dsp.window.close()')
B.bind(key(mod, "F"), "Fullscreen",               'hl.dsp.window.fullscreen()')
B.bind(key(mod, "T"), "Float or tile window",     'hl.dsp.window.float({ action = "toggle" })')
B.bind(key(mod, "P"), "Pseudo-tile window",       'hl.dsp.window.pseudo()')
B.bind(key(mod, "J"), "Toggle split direction",   'hl.dsp.layout("togglesplit")')

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    -- Focus
    B.bind(key(mod, dir), "Focus " .. dir, ('hl.dsp.focus({ direction = "%s" })'):format(dir))
    -- Move window
    B.bind(key(mod, "SHIFT", dir), "Move window " .. dir, ('hl.dsp.window.move({ direction = "%s" })'):format(dir))
end

-- Resize (repeats while held)
local held_resize = { repeating = true, menu = false }
B.bind(key(mod, "CTRL", "left"),  "Resize window narrower", 'hl.dsp.window.resize({ x = -40, y = 0, relative = true })', held_resize)
B.bind(key(mod, "CTRL", "right"), "Resize window wider",    'hl.dsp.window.resize({ x = 40, y = 0, relative = true })',  held_resize)
B.bind(key(mod, "CTRL", "up"),    "Resize window shorter",  'hl.dsp.window.resize({ x = 0, y = -40, relative = true })', held_resize)
B.bind(key(mod, "CTRL", "down"),  "Resize window taller",   'hl.dsp.window.resize({ x = 0, y = 40, relative = true })',  held_resize)

-- Mouse: drag with left = move, right = resize
B.bind(key(mod, "mouse:272"), "Drag to move window",   'hl.dsp.window.drag()',   { mouse = true })
B.bind(key(mod, "mouse:273"), "Drag to resize window", 'hl.dsp.window.resize()', { mouse = true })

-- --- Workspaces -------------------------------------------------------
B.group("ws-go",   "Go to workspace",          key(mod, "1…0"),          "Workspace")
B.group("ws-move", "Move window to workspace", key(mod, "SHIFT", "1…0"), "Workspace")
for i = 1, 10 do
    local k = tostring(i % 10) -- workspace 10 is on key 0
    B.bind(key(mod, k),          tostring(i), ("hl.dsp.focus({ workspace = %d })"):format(i),       { group = "ws-go" })
    B.bind(key(mod, "SHIFT", k), tostring(i), ("hl.dsp.window.move({ workspace = %d })"):format(i), { group = "ws-move" })
end

B.bind(key(mod, "mouse_down"), "Next workspace (scroll)",     'hl.dsp.focus({ workspace = "e+1" })')
B.bind(key(mod, "mouse_up"),   "Previous workspace (scroll)", 'hl.dsp.focus({ workspace = "e-1" })')

-- --- Screenshots (hyprshot: clipboard + ~/Pictures/Screenshots) ---------
B.bind("Print",                "Screenshot a region",  'hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots")')
B.bind(key("SHIFT", "Print"),  "Screenshot a window",  'hl.dsp.exec_cmd("hyprshot -m window -o ~/Pictures/Screenshots")')
B.bind(key("CTRL", "Print"),   "Screenshot a monitor", 'hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures/Screenshots")')

-- --- Media keys (work when locked, volume/brightness repeat when held) ---
local held = { locked = true, repeating = true }
local locked = { locked = true }
B.bind("XF86AudioRaiseVolume",  "Volume up",         'hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+")', held)
B.bind("XF86AudioLowerVolume",  "Volume down",       'hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-")', held)
B.bind("XF86AudioMute",         "Mute",              'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")', locked)
B.bind("XF86AudioMicMute",      "Mute microphone",   'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")', locked)
B.bind("XF86MonBrightnessUp",   "Brightness up",     'hl.dsp.exec_cmd("brightnessctl set 5%+")', held)
B.bind("XF86MonBrightnessDown", "Brightness down",   'hl.dsp.exec_cmd("brightnessctl set 5%-")', held)
B.bind("XF86AudioPlay",         "Play or pause",     'hl.dsp.exec_cmd("playerctl play-pause")', locked)
B.bind("XF86AudioPause",        "Play or pause",     'hl.dsp.exec_cmd("playerctl play-pause")', locked)
B.bind("XF86AudioNext",         "Next track",        'hl.dsp.exec_cmd("playerctl next")', locked)
B.bind("XF86AudioPrev",         "Previous track",    'hl.dsp.exec_cmd("playerctl previous")', locked)
