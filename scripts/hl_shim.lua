-- scripts/hl_shim.lua
hl = {}
col = {}

local keybind_callbacks = {}

-- Virtual key code mapper for Windows
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
            mod = mod + 0x0001 -- Map to Alt (MOD_ALT) for stability
        elseif p == "SHIFT" then
            mod = mod + 0x0004 -- MOD_SHIFT
        elseif p == "CONTROL" or p == "CTRL" then
            mod = mod + 0x0002 -- MOD_CONTROL
        elseif p == "ALT" then
            mod = mod + 0x0001 -- MOD_ALT
        end
    end

    local key = parts[#parts]
    if #key == 1 then
        vk = string.byte(key)
    else
        local special_keys = {
            ["LEFT"] = 0x25, ["UP"] = 0x26, ["RIGHT"] = 0x27, ["DOWN"] = 0x28,
            ["RETURN"] = 0x0D, ["ENTER"] = 0x0D, ["SPACE"] = 0x20,
            ["TAB"] = 0x09, ["ESCAPE"] = 0x1B
        }
        vk = special_keys[key] or 0
    end

    return mod, vk
end

-- Config bridge (Translates Hyprland config structure to HyprWin theme tokens)
hl.config = function(cfg)
    if not cfg then return end
    local t = HyprWin.theme

    if cfg.general then
        t.gaps_in = cfg.general.gaps_in or t.gaps_in
        t.gaps_out = cfg.general.gaps_out or t.gaps_out
        t.border_size = cfg.general.border_size or t.border_size
        HyprWin.layout_mode = cfg.general.layout or HyprWin.layout_mode
    end

    if cfg.decoration then
        t.rounding = cfg.decoration.rounding or t.rounding
    end

    if cfg.animations then
        HyprWin.anim_active = cfg.animations.enabled
    end
end

-- Fake stubs for features not yet ported
hl.monitor = function() end
hl.on = function() end
hl.env = function() end
hl.curve = function() end
hl.animation = function() end
hl.window_rule = function() end

-- Dispatchers namespace (hl.dsp.*)
hl.dsp = {
    exec_cmd = function(cmd)
        return function() wm.spawn(cmd) end
    end,
    exit = function()
        os.exit()
    end,
    window = {
        close = function()
            local focused = HyprWin.focused_window
            if focused then wm.close_window(focused) end
        end,
        float = function()
            return function()
                local focused = HyprWin.focused_window
                if focused then
                    if HyprWin.floating_windows[focused] then
                        HyprWin.floating_windows[focused] = nil
                    else
                        HyprWin.floating_windows[focused] = true
                    end
                    HyprWin.retile()
                end
            end
        end
    },
    movefocus = function(dir)
        local dir_map = { l = "left", r = "right", u = "up", d = "down" }
        return function()
            local target = dir_map[dir]
            if target then
                local neighbor = find_neighbor(target)
                if neighbor then wm.focus_window(neighbor) end
            end
        end
    },
    workspace = function(ws_name)
        local ws_num = tonumber(ws_name)
        return function()
            if ws_num and ws_num ~= HyprWin.current_workspace then
                HyprWin.current_workspace = ws_num
                HyprWin.retile()
            end
        end
    },
    movetoworkspace = function(ws_name)
        local ws_num = tonumber(ws_name)
        return function()
            local focused = HyprWin.focused_window
            if focused and ws_num then
                HyprWin.window_workspaces[focused] = ws_num
                HyprWin.retile()
            end
        end
    }
end

-- Hotkey registration mapping
hl.bind = function(combo, action, opts)
    local mod, vk = parse_key_combo(combo)
    if vk == 0 then return end

    local id = #keybind_callbacks + 1000
    keybind_callbacks[id] = action
    wm.register_hotkey(id, mod, vk)
end

-- Main hotkey callback dispatcher called from C++
HyprWin.on_hotkey = function(id)
    local callback = keybind_callbacks[id]
    if callback then
        if type(callback) == "function" then
            callback()
        end
    end
end