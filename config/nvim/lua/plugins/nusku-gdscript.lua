-- Nusku: GDScript support when GDScript (Godot) was picked in the installer.
-- The language server is Godot's own (127.0.0.1:6005), running only while the Godot editor is open;
-- Mason has nothing to install for it.
if not require("nusku.languages").has("gdscript") then
  return {}
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gdscript = { mason = false },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "gdscript", "godot_resource", "gdshader" } },
  },
}
