-- Nusku - short, snappy animations (speeds are in 100 ms units, so all <= 300 ms).

hl.config({ animations = { enabled = true } })

hl.curve("ease", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })
hl.curve("snap", { type = "bezier", points = { { 0.2, 0.9 }, { 0.3, 1.0 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 2.5, bezier = "snap", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2,   bezier = "ease", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 2.5, bezier = "ease" })
hl.animation({ leaf = "border",     enabled = true, speed = 3,   bezier = "ease" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "snap", style = "slide" })
