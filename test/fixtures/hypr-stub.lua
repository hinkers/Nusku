-- Minimal stand-in for Hyprland's `hl` table, so config modules run under `nvim -l`.
-- Usage: nvim -l test/fixtures/hypr-stub.lua MODULE.lua [EVENT]
-- Loads MODULE, fires EVENT's handlers (default hyprland.start), prints one line per
-- recorded hl.exec_cmd call.
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

local function fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        fn(...)
    end
end

local module, event = arg[1], arg[2] or "hyprland.start"
if module then
    dofile(module)
    fire(event)
    for _, cmd in ipairs(calls.exec) do
        print(cmd)
    end
end
