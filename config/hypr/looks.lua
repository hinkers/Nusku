-- Nusku - general look: gaps, borders, rounding, blur, shadow. Colours come from the palette.

local colors = require(require("paths").theme .. "/hypr-colors")

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = colors.accent,
            inactive_border = colors.surface0,
        },
        layout = "dwindle",
        resize_on_border = true,
    },

    decoration = {
        rounding = 10,

        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            vibrancy = 0.15,
        },

        shadow = {
            enabled = true,
            range = 12,
            render_power = 3,
            color = colors.crust,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = colors.base,
        force_default_wallpaper = 0,
    },
})
