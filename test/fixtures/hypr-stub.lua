-- Minimal stand-in for Hyprland's `hl` table, so config modules run under `nvim -l`.
-- Usage: nvim -l test/fixtures/hypr-stub.lua MODULE.lua [EVENT]
-- Loads MODULE, fires EVENT's handlers (default hyprland.start), prints one line per
-- recorded hl.exec_cmd call.
-- Env:
--   HYPR_STUB_REPORT=binds  print one "keys<TAB>description<TAB>opt,names" line per hl.bind call instead
--   HYPR_STUB_LOADS=N       load MODULE N times (a config reload), default 1
--   HYPR_STUB_EXISTS=P:Q    io.open(P, "r") succeeds for these paths (fake empty file)
--   HYPR_STUB_MISSING=P:Q   io.open(P, "r") fails for these paths
-- `require` resolves from MODULE's directory, then config/hypr/.
local calls = { exec = {}, bind = {}, dsp = {} }
local handlers = {}

local function recorder(path)
    return setmetatable({}, {
        __index = function(_, name)
            return recorder(path .. "." .. name)
        end,
        __call = function(_, ...)
            table.insert(calls.dsp, { path = path, args = { ... } })
            return { dsp = path, args = { ... } }
        end,
    })
end

hl = {
    on = function(event, fn)
        handlers[event] = handlers[event] or {}
        table.insert(handlers[event], fn)
    end,
    exec_cmd = function(cmd)
        table.insert(calls.exec, cmd)
    end,
    bind = function(...)
        table.insert(calls.bind, { ... })
    end,
    dsp = recorder("hl.dsp"),
}

local function pathset(var)
    local set = {}
    for p in (os.getenv(var) or ""):gmatch("[^:]+") do
        set[p] = true
    end
    return set
end

local exists, missing = pathset("HYPR_STUB_EXISTS"), pathset("HYPR_STUB_MISSING")
local real_open = io.open
io.open = function(path, mode)
    if (mode == nil or mode == "r") and missing[path] then
        return nil, path .. ": No such file or directory"
    end
    if (mode == nil or mode == "r") and exists[path] then
        return { close = function() end, read = function() return "" end, lines = function() return function() end end }
    end
    return real_open(path, mode)
end

local function fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        fn(...)
    end
end

local module, event = arg[1], arg[2] or "hyprland.start"
if module then
    local here = (arg[0] or ""):match("^(.*)/[^/]*$") or "."
    local dir = module:match("^(.*)/[^/]*$") or "."
    package.path = dir .. "/?.lua;" .. here .. "/../../config/hypr/?.lua;" .. package.path
    for _ = 1, tonumber(os.getenv("HYPR_STUB_LOADS") or "1") do
        dofile(module)
    end
    fire(event)
    if os.getenv("HYPR_STUB_REPORT") == "binds" then
        for _, b in ipairs(calls.bind) do
            local names = {}
            for k in pairs(b[3] or {}) do
                table.insert(names, k)
            end
            table.sort(names)
            print(b[1] .. "\t" .. tostring((b[3] or {}).description) .. "\t" .. table.concat(names, ","))
        end
    else
        for _, cmd in ipairs(calls.exec) do
            print(cmd)
        end
    end
end
