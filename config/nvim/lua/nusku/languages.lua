-- Nusku: LazyVim language extras for the languages picked in the installer.
-- The installer writes ~/.config/nusku/nvim-languages.lua (`return { "python", ... }`) from
-- LANGS; lua/config/lazy.lua imports the extras below for each listed language. Extras you
-- enable yourself with :LazyExtras go to lazyvim.json as usual.
local M = {}

-- Catalogue id (packages/apps.list) -> LazyVim extras under lazyvim.plugins.extras.
-- false: nothing to import (LazyVim's core covers Lua; GDScript has lua/plugins/nusku-gdscript.lua).
M.extras = {
  python = { "lang.python" },
  php = { "lang.php" },
  gdscript = false,
  js = { "lang.typescript", "lang.json" },
  rust = { "lang.rust" },
  go = { "lang.go" },
  cpp = { "lang.clangd", "lang.cmake" },
  csharp = { "lang.dotnet" },
  java = { "lang.java" },
  lua = false,
}

M.file = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/nusku/nvim-languages.lua"

---@return string[] the picked language ids; {} when the file is missing or broken
function M.enabled()
  local ok, langs = pcall(dofile, M.file)
  if not ok or type(langs) ~= "table" then
    return {}
  end
  return langs
end

---@param id string
function M.has(id)
  return vim.tbl_contains(M.enabled(), id)
end

---@return LazySpec[] one { import = ... } spec per extra of the picked languages
function M.imports()
  local specs = {}
  for _, id in ipairs(M.enabled()) do
    for _, extra in ipairs(M.extras[id] or {}) do
      specs[#specs + 1] = { import = "lazyvim.plugins.extras." .. extra }
    end
  end
  return specs
end

return M
