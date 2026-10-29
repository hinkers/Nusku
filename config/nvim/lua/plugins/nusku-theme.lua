-- Nusku: Catppuccin Mocha with the accent chosen in the installer
-- (~/.config/nusku/theme/nvim-accent.lua, rendered from theme/templates/nvim-accent.lua.tmpl).
local function accent()
  local file = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/nusku/theme/nvim-accent.lua"
  local ok, a = pcall(dofile, file)
  if ok and type(a) == "table" and type(a.hex) == "string" then
    return a.hex
  end
  return "#89b4fa" -- Catppuccin Mocha blue, Nusku's default accent
end

return {
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin-mocha" },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "mocha",
      custom_highlights = function()
        local hex = accent()
        return {
          CursorLineNr = { fg = hex },
          FloatBorder = { fg = hex },
          WinSeparator = { fg = hex },
          Title = { fg = hex },
        }
      end,
    },
  },
}
