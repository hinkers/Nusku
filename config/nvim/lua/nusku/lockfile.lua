-- Nusku: where lazy.nvim keeps its lockfile.
-- lazy.nvim rewrites its lockfile with only the plugins in use, so the repo's lazy-lock.json
-- (Nusku's pins, covering every language's extras) would lose the other languages' plugins and
-- leave the checkout dirty. lazy.nvim therefore uses a copy in ~/.local/share/nvim: seeded from
-- the repo's file when missing, and reset to it by the installer's headless sync (nusku.sync).
-- To bump Nusku's pins, regenerate config/nvim/lazy-lock.json with every language enabled.
local M = {}

M.repo = vim.fn.stdpath("config") .. "/lazy-lock.json"
M.path = vim.fn.stdpath("data") .. "/lazy-lock.json"

---@param force? boolean overwrite an existing copy
---@return boolean ok
function M.seed(force)
  if not force and vim.uv.fs_stat(M.path) then
    return true
  end
  vim.fn.mkdir(vim.fn.fnamemodify(M.path, ":h"), "p")
  return vim.uv.fs_copyfile(M.repo, M.path) == true
end

return M
