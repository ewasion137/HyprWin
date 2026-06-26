-- scripts/hl_shim.lua
hl = {}
col = {}

local keybind_callbacks = {}

local window_rules = {
    float = { "Telegram", "Picture-in-picture", "Calculator", "Картинка в картинке" },
    ignore_classes = { 
        "Chrome_ChildWin_Templ", "HyprWinOverlay", "GhostWindow", 
        "DesktopWindowXamlSource", "MSCTFIME UI", "IME", "CicMarshalWnd",
        "TaskManagerWindow"
    }
}

-- Hex parser supporting both #RRGGBBAA and #RRGGBB
local function parse_rgba_string(str)
    if not str then return nil end
    local hex = str:match("rgba?%((%x+)%)") or str:match("0x(%x+)")
    if not hex then
        hex = str:gsub("^#", ""):gsub("^0x", "")
    end
    
    if hex then
        hex = hex:trim()
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
            mod = mod + 0x0001 -- Map Super/Win to Alt safely on Windows
        elseif p == "SHIFT" then
            mod = mod + 0x0004
        elseif p == "CONTROL" or p == "CTRL" then
            mod = mod + 0x0002
        elseif p == "ALT" then
            mod = mod + 0x0001
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
        HyprWin.layout_mode = cfg.general.layout or HyprWin.layout_mode
        
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

-- Structural Translation for complex official Windows and Workspace Rules
hl.window_rule = function(rule)
    if not rule or not rule.match then return end
    if rule.float then
        if rule.match.class then
            for pattern in string.gmatch(rule.match.class, "[^|]+") do
                table.insert(window_rules.float, pattern:trim())
            end
        end
        if rule.match.title then
            for pattern in string.gmatch(rule.match.title, "[^|]+") do
                table.insert(window_rules.float, pattern:trim())
            end
        end
    end
end

hl.workspace_rule = function() end
hl.layer_rule = function() end
hl.monitor = function() end
hl.on = function() end
hl.env = function() end
hl.curve = function() end
hl.animation = function() end
hl.gesture = function() end
hl.device = function() end

-- Emulator for the official Dispatcher Namespace
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
        end,
        fullscreen = function()
            return function()
                local focused = HyprWin.focused_window
                if focused then
                    if HyprWin.fullscreen_windows[focused] then
                        HyprWin.fullscreen_windows[focused] = nil
                    else
                        HyprWin.fullscreen_windows[focused] = true
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
    end, -- Closes movefocus function
    workspace = function(ws_name)
        local ws_num = tonumber(ws_name)
        return function()
            if ws_num and ws_num ~= HyprWin.current_workspace then
                HyprWin.current_workspace = ws_num
                HyprWin.retile()
            end
        end
    end, -- Closes workspace function
    movetoworkspace = function(ws_name)
        local ws_num = tonumber(ws_name)
        return function()
            local focused = HyprWin.focused_window
            if focused and ws_num then
                HyprWin.window_workspaces[focused] = ws_num
                HyprWin.retile()
            end
        end
    end -- Closes movetoworkspace function
}

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