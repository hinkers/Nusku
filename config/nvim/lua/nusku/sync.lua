-- Nusku: headless first-time setup, run by the installer (lib/apps.sh, apps_hook_neovim):
--   nvim --headless "+lua require('nusku.sync').run()"
-- Installs exactly the lazy-lock.json plugin revisions, then every Mason tool and treesitter
-- parser the enabled LazyVim specs ask for, so the first real launch has nothing left to install.
-- Exits 0 when everything is in place; otherwise prints what failed and exits 1.
local M = {}

local MASON_TIMEOUT = 15 * 60 * 1000
local PARSER_TIMEOUT = 10 * 60 * 1000

local function say(msg)
  io.stdout:write("\nnusku.sync: " .. msg .. "\n")
end

local function fail(msg)
  io.stderr:write("\nnusku.sync: FAILED: " .. msg .. "\n")
  vim.cmd.cquit(1)
end

local function plugin(name)
  return require("lazy.core.config").plugins[name]
end

-- The resolved opts of a plugin spec (every spec fragment and opts function merged).
local function opts(name)
  local p = plugin(name)
  return p and require("lazy.core.plugin").values(p, "opts", false) or {}
end

local function plugins()
  local Plugin = require("lazy.core.plugin")
  local bad = {}
  -- Reset lazy.nvim's lockfile to the repo's pins and make lazy.nvim re-read it.
  if not require("nusku.lockfile").seed(true) then
    return "could not copy " .. require("nusku.lockfile").repo
  end
  require("lazy.manage.lock")._loaded = false
  require("lazy").restore({ wait = true, show = false })
  for name, p in pairs(require("lazy.core.config").plugins) do
    if not p._.installed or Plugin.has_errors(p) then
      bad[#bad + 1] = name
    end
  end
  table.sort(bad)
  if #bad > 0 then
    return "plugins not installed: " .. table.concat(bad, ", ")
  end
  local names = vim.tbl_keys(require("lazy.core.config").plugins)
  table.sort(names)
  require("lazy").load({ plugins = names })
  say(("%d plugins at their lazy-lock.json revisions"):format(#names))
end

-- Mason packages: mason's own ensure_installed plus the LSP servers LazyVim hands to
-- mason-lspconfig (which skips its own ensure_installed when headless).
local function mason_packages()
  local wanted, seen = {}, {}
  local function add(name)
    if name and not seen[name] then
      seen[name] = true
      wanted[#wanted + 1] = name
    end
  end
  for _, name in ipairs(opts("mason.nvim").ensure_installed or {}) do
    add(name)
  end
  if plugin("mason-lspconfig.nvim") then
    local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
    local settings = require("mason-lspconfig.settings").current
    for _, server in ipairs(settings.ensure_installed or {}) do
      add(map[server] or server)
    end
  end
  return wanted
end

local function mason()
  local mr = require("mason-registry")
  local refreshed = false
  mr.refresh(function()
    refreshed = true
  end)
  if not vim.wait(MASON_TIMEOUT, function()
    return refreshed
  end, 200) then
    return "Mason registry did not refresh"
  end

  local wanted = mason_packages()
  local failed = {} ---@type table<string, string>
  vim.schedule(function()
    for _, name in ipairs(wanted) do
      if not mr.has_package(name) then
        failed[name] = "unknown Mason package"
      else
        local p = mr.get_package(name)
        if not p:is_installed() and not p:is_installing() then
          p:install({}, function(ok, err)
            if not ok then
              failed[name] = tostring(err)
            end
          end)
        end
      end
    end
  end)
  vim.wait(200)

  local function done()
    for _, name in ipairs(wanted) do
      if not failed[name] then
        local p = mr.get_package(name)
        if p:is_installing() or not p:is_installed() then
          return false
        end
      end
    end
    return true
  end
  if not vim.wait(MASON_TIMEOUT, done, 500) then
    return "Mason tools still installing after 15 minutes"
  end
  local bad = {}
  for _, name in ipairs(wanted) do
    if failed[name] then
      bad[#bad + 1] = name .. " (" .. failed[name] .. ")"
    end
  end
  if #bad > 0 then
    return "Mason tools not installed: " .. table.concat(bad, "; ")
  end
  say(("%d Mason tools ready: %s"):format(#wanted, table.concat(wanted, ", ")))
end

local function parsers()
  local wanted = opts("nvim-treesitter").ensure_installed or {}
  local TS = require("nvim-treesitter")
  local ok, err = pcall(function()
    TS.install(wanted):wait(PARSER_TIMEOUT)
  end)
  if not ok then
    return "treesitter install: " .. tostring(err)
  end
  local have = {}
  for _, lang in ipairs(TS.get_installed("parsers")) do
    have[lang] = true
  end
  local bad = vim.tbl_filter(function(lang)
    return not have[lang]
  end, wanted)
  if #bad > 0 then
    return "treesitter parsers not installed: " .. table.concat(bad, ", ")
  end
  say(("%d treesitter parsers ready"):format(#wanted))
end

function M.run()
  for _, step in ipairs({ plugins, mason, parsers }) do
    local ok, err = pcall(step)
    if not ok or err then
      return fail(tostring(err))
    end
  end
  say("done")
  vim.cmd("qa!")
end

return M
