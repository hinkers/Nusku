-- Nusku - keybind helper. Every bind gets a plain-words description (shown by Hyprland and
-- by the SUPER + / keybind menu) and a record in ${XDG_RUNTIME_DIR}/nusku/keybinds.tsv:
--   kind<TAB>group<TAB>keys<TAB>desc<TAB>runnable<TAB>expr
-- kind is "bind" or "group". expr is the dispatcher as a Lua expression, which the menu
-- runs with `hyprctl dispatch "<expr>"`. Group records hold the prompt in the expr column.

local B = {}

local function manifest_path()
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime == nil or runtime == "" then
        return nil
    end
    return runtime .. "/nusku/keybinds.tsv"
end

local function clean(value)
    return (tostring(value or ""):gsub("[\t\r\n]", " "))
end

local function append(kind, group, keys, desc, runnable, expr)
    local path = manifest_path()
    if path == nil then
        return
    end
    local f = io.open(path, "a")
    if f == nil then
        return
    end
    f:write(table.concat({ clean(kind), clean(group), clean(keys), clean(desc), clean(runnable), clean(expr) }, "\t"), "\n")
    f:close()
end

-- Truncate the manifest (called once at the top of keybinds.lua, so a reload rewrites it).
function B.reset()
    local path = manifest_path()
    if path == nil then
        return
    end
    local f = io.open(path, "w")
    if f == nil then
        os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$"):gsub("'", "'\\''") .. "'")
        f = io.open(path, "w")
    end
    if f then
        f:close()
    end
end

-- B.bind(keys, desc, expr, opts): opts are hl.bind's, plus `group = "<id>"` for the menu.
function B.bind(keys, desc, expr, opts)
    if desc == nil or desc == "" then
        error("bindlib: a description is required for " .. tostring(keys), 2)
    end
    local chunk, err = load("return " .. expr, "=bind " .. tostring(keys))
    if chunk == nil then
        error("bindlib: bad dispatcher for " .. tostring(keys) .. ": " .. err, 2)
    end

    local bind_opts = { description = desc }
    local group = ""
    for k, v in pairs(opts or {}) do
        if k == "group" then
            group = v
        else
            bind_opts[k] = v
        end
    end

    hl.bind(keys, chunk(), bind_opts)

    -- Drag and held (repeating) binds make no sense as a one-off run from the menu.
    local runnable = (bind_opts.mouse or bind_opts.repeating or keys:lower():find("mouse", 1, true)) and "0" or "1"
    append("bind", group, keys, desc, runnable, expr)
end

-- B.group(id, desc, keys_summary, prompt): one collapsed menu line for binds with opts.group = id.
function B.group(id, desc, keys_summary, prompt)
    append("group", id, keys_summary, desc, "1", prompt)
end

return B
