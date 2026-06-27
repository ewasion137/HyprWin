-- scripts/hl_shim.lua
hl = {}
col = {}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

HyprWin.custom_hotkeys = HyprWin.custom_hotkeys or {}
HyprWin.custom_hotkey_counter = HyprWin.custom_hotkey_counter or 0

-- Global storage for active layout rules and curve engines
HyprWin.window_rules = { float = {}, rules_list = {} }
HyprWin.workspace_rules = {}
HyprWin.curves = {}
HyprWin.animations = {}
HyprWin.monitors = {}

-- Hex parser supporting both #RRGGBBAA and #RRGGBB
local function parse_rgba_string(str)
    if not str then return nil end
    local hex = str:match("rgba?%((%x+)%)") or str:match("0x(%x+)")
    if not hex then
        hex = str:gsub("^#", ""):gsub("^0x", "")
    end
    
    if hex then
        hex = trim(hex)
        if #hex == 6 then
            local r = tonumber(hex:sub(1, 2), 16) / 255
            local g = tonumber(hex:sub(3, 4), 16) / 255
            local b = tonumber(hex:sub(5, 6), 16) / 255
            return { r, g, b, 1.0 }
        elseif #hex == 8 then
            local a = tonumber(hex:sub(1, 2), 16) / 255
            local r = tonumber(hex:sub(3, 4), 16) / 255
            local g = tonumber(hex:sub(5, 6), 16) / 255
            local b = tonumber(hex:sub(7, 8), 16) / 255
            return { r, g, b, a }
        end
    end
    return nil
end

local function parse_key_combo(combo)
    local parts = {}
    for part in string.gmatch(combo, "[^+%s]+") do
        table.insert(parts, part:upper())
    end

    local mod = 0
    local vk = 0

    for i = 1, #parts - 1 do
        local p = parts[i]
        if p == "SUPER" or p == "WIN" then
            mod = mod + 0x0008  -- MOD_WIN
        elseif p == "SHIFT" then
            mod = mod + 0x0004  -- MOD_SHIFT
        elseif p == "CONTROL" or p == "CTRL" then
            mod = mod + 0x0002  -- MOD_CONTROL
        elseif p == "ALT" then
            mod = mod + 0x0001  -- MOD_ALT
        end
    end

    local key = parts[#parts]
    if #key == 1 then
        vk = string.byte(key)
    else
        local special_keys = {
            ["LEFT"] = 0x25, ["UP"] = 0x26, ["RIGHT"] = 0x27, ["DOWN"] = 0x28,
            ["RETURN"] = 0x0D, ["ENTER"] = 0x0D, ["SPACE"] = 0x20,
            ["TAB"] = 0x09, ["ESCAPE"] = 0x1B, ["DELETE"] = 0x2E,
            ["GRAVE"] = 0xC0, ["BACKSLASH"] = 0xDC, ["BACKSPACE"] = 0x08,
            ["BRACKETLEFT"] = 0xDB, ["BRACKETRIGHT"] = 0xDD,
            ["PERIOD"] = 0xBE, ["COMMA"] = 0xBC, ["SLASH"] = 0xBF,
            ["SEMICOLON"] = 0xBA, ["APOSTROPHE"] = 0xDE, ["PRINT"] = 0x2C
        }
        vk = special_keys[key] or 0
    end

    return mod, vk
end

hl.config = function(cfg)
    if not cfg then return end
    local t = HyprWin.theme

    if cfg.general then
        t.gaps_in = cfg.general.gaps_in or t.gaps_in
        t.gaps_out = cfg.general.gaps_out or t.gaps_out
        t.border_size = cfg.general.border_size or t.border_size
        
        local layout = cfg.general.layout
        if layout == "dwindle" or layout == "scrolling" or layout == "tabbed" then
            HyprWin.layout_mode = "bsp"
        elseif layout then
            HyprWin.layout_mode = layout
        end
        
        if cfg.general.col then
            local act = parse_rgba_string(cfg.general.col.active_border)
            if act then t.active_border_color = act; t.accent_color = act end
            local inact = parse_rgba_string(cfg.general.col.inactive_border)
            if inact then t.border_color = inact end
        end
    end

    if cfg.decoration then
        t.rounding = cfg.decoration.rounding or t.rounding
    end

    if cfg.animations then
        HyprWin.anim_active = cfg.animations.enabled
    end
end

-- Collect structured window rules for execution
hl.window_rule = function(rule)
    if not rule or not rule.match then return end
    table.insert(HyprWin.window_rules.rules_list, rule)

    if rule.float then
        if rule.match.class then
            for pattern in string.gmatch(rule.match.class, "[^|]+") do
                table.insert(HyprWin.window_rules.float, trim(pattern))
            end
        end
        if rule.match.title then
            for pattern in string.gmatch(rule.match.title, "[^|]+") do
                table.insert(HyprWin.window_rules.float, trim(pattern))
            end
        end
    end
end

-- Track active workspace layout bindings
hl.workspace_rule = function(rule)
    if not rule or not rule.workspace then return end
    local ws = tonumber(rule.workspace) or rule.workspace
    if rule.layout then
        local layout = rule.layout
        -- Map Linux-only layouts to supported Windows equivalents
        if layout == "dwindle" or layout == "scrolling" or layout == "tabbed" then
            layout = "bsp"
        end
        HyprWin.workspace_rules[ws] = layout
    end
end

-- Save custom mathematical animation curves
hl.curve = function(name, def)
    if not name or not def then return end
    HyprWin.curves[name] = def
end

-- Save specific leaf animation speeds and styles
hl.animation = function(rule)
    if not rule or not rule.leaf then return end
    HyprWin.animations[rule.leaf] = rule
end

-- Track display scale and workspace configurations
hl.monitor = function(rule)
    if not rule then return end
    table.insert(HyprWin.monitors, rule)
end

hl.layer_rule = function() end
hl.on = function() end
hl.env = function() end
hl.gesture = function() end
hl.device = function() end

local function parse_workspace(ws_name)
    local ws_num = tonumber(ws_name)
    if not ws_num then
        if ws_name == "e+1" or ws_name == "m+1" then
            ws_num = math.min(10, HyprWin.current_workspace + 1)
        elseif ws_name == "e-1" or ws_name == "m-1" then
            ws_num = math.max(1, HyprWin.current_workspace - 1)
        end
    end
    return ws_num or ws_name
end

HyprWin.active_special_workspace = nil

-- Smart callable table for workspace dispatcher
local workspace_dispatcher = setmetatable({
    toggle_special = function(name)
        return function()
            local special_ws = "special:" .. name
            if HyprWin.active_special_workspace == special_ws then
                -- Hide the scratchpad (stash windows back)
                HyprWin.active_special_workspace = nil
            else
                -- Reveal scratchpad over current layout
                HyprWin.active_special_workspace = special_ws
            end
            HyprWin.retile()
        end
    end
}, {
    __call = function(self, ws_name)
        return function()
            local ws = parse_workspace(ws_name)
            if type(ws) == "number" and ws ~= HyprWin.current_workspace then
                if HyprWin.switch_workspace then
                    HyprWin.switch_workspace(ws)
                else
                    HyprWin.current_workspace = ws
                    HyprWin.retile()
                end
            end
        end
    end
})

hl.dsp = {
    exec_cmd = function(cmd)
        return function() wm.spawn(cmd) end
    end,
    exit = function()
        return function() os.exit() end
    end,
    window = {
        close = function()
            return function()
                local focused = HyprWin.focused_window
                if focused then wm.close_window(focused) end
            end
        end,
        float = function()
            return function()
                local focused = HyprWin.focused_window
                if focused then
                    HyprWin.floating_windows[focused] = not HyprWin.floating_windows[focused]
                    HyprWin.retile()
                end
            end
        end,
        fullscreen = function()
            return function()
                local focused = HyprWin.focused_window
                if focused then
                    HyprWin.fullscreen_windows[focused] = not HyprWin.fullscreen_windows[focused]
                    HyprWin.retile()
                end
            end
        end,
        -- Fully implemented window placement and swapping dispatcher
        move = function(opts)
            return function()
                local focused = HyprWin.focused_window
                if not focused then return end
                
                if opts then
                    if opts.workspace then
                        -- Move focused window to specific workspace (e.g. 2 or "special:magic")
                        local ws = parse_workspace(opts.workspace)
                        HyprWin.window_workspaces[focused] = ws
                        HyprWin.retile()
                    elseif opts.direction then
                        -- Swap windows in a spatial direction
                        local dir_map = { l = "left", r = "right", u = "up", d = "down" }
                        local target = dir_map[opts.direction] or opts.direction
                        if swap_direction then swap_direction(target) end
                    end
                end
            end
        end,
        cycle_next = function() return function() end end,
        pseudo = function() return function() end end,
        drag = function() return function() end end,
        resize = function() return function() end end
    },
    focus = function(opts)
        return function()
            if opts then
                if opts.direction then
                    local dir_map = { l = "left", r = "right", u = "up", d = "down" }
                    local target = dir_map[opts.direction] or opts.direction
                    if find_neighbor then
                        local neighbor = find_neighbor(target)
                        if neighbor then wm.focus_window(neighbor) end
                    end
                elseif opts.workspace then
                    local ws = parse_workspace(opts.workspace)
                    if type(ws) == "number" and ws ~= HyprWin.current_workspace then
                        if HyprWin.switch_workspace then
                            HyprWin.switch_workspace(ws)
                        else
                            HyprWin.current_workspace = ws
                            HyprWin.retile()
                        end
                    end
                end
            end
        end
    end,
    layout = function(mode)
        return function() end
    end,
    dpms = function() return function() end end,
    workspace = workspace_dispatcher, -- Register the smart workspace dispatcher
    movetoworkspace = function(ws_name)
        return function()
            local focused = HyprWin.focused_window
            if focused then
                local ws = parse_workspace(ws_name)
                HyprWin.window_workspaces[focused] = ws
                HyprWin.retile()
            end
        end
    end
}

hl.bind = function(combo, action, opts)
    local mod, vk = parse_key_combo(combo)
    if vk == 0 then return end

    HyprWin.custom_hotkey_counter = HyprWin.custom_hotkey_counter + 1
    local id = HyprWin.custom_hotkey_counter + 1000
    HyprWin.custom_hotkeys[id] = action
    wm.register_hotkey(id, mod, vk)
end