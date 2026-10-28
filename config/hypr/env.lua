-- Nusku - environment for everything started from the session.

-- Note: values are not shell-expanded ($HOME, $PATH stay literal), so PATH is not set here.

local cursor = require(require("paths").theme .. "/hypr-cursor")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Catppuccin cursor in the accent colour (theme name comes from the palette).
hl.env("XCURSOR_THEME", cursor.theme)
hl.env("HYPRCURSOR_THEME", cursor.theme)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Toolkit hints
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
