-- scripts/main.lua
HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
HyprWin.current_workspace = 1
HyprWin.window_workspaces = {} 
HyprWin.floating_windows = {}  
HyprWin.floating_rects = {}    
HyprWin.sticky_windows = {}    
HyprWin.fullscreen_windows = {} 
HyprWin.workspace_ratios = {}  
HyprWin.layout_mode = "bsp"
HyprWin.anim_speed = 0.15
local is_retiling = false

-- --- THEME DESIGN SYSTEM TOKENS ---
HyprWin.theme = {
    gaps_in = 5,
    gaps_out = 15,
    border_size = 2,
    rounding = 8,
    font_family = "Segoe UI Variable",
    icon_font_family = "Segoe MDL2 Assets",
    
    -- Color channels: {R, G, B, A}
    bg_color = { 0.02, 0.02, 0.03, 0.90 },
    border_color = { 0.15, 0.15, 0.18, 0.60 },
    active_border_color = { 0.70, 0.40, 1.00, 1.00 },
    accent_color = { 0.70, 0.40, 1.00, 1.00 },
    accent_teal = { 0.20, 0.80, 0.70, 1.00 },
    accent_danger = { 0.90, 0.25, 0.35, 1.00 },
    text_color = { 0.85, 0.85, 0.95, 0.90 },
    text_dim = { 0.55, 0.55, 0.60, 0.80 },
    
    bar_height = 30
}

package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua;./scripts/?/init.lua"

local topbar = require("topbar")
local alttab = require("alttab")
local launcher = require("launcher")
local hl_shim = require("hl_shim")

local config_path = wm.get_config_path()
local success, err = pcall(dofile, config_path)
if not success then
    log("CONFIG ERROR: " .. tostring(err))
end

-- Parser for 0xff7040ff / 0x7040ff hex colors
local function parse_hex_color(hex)
    if not hex then return nil end
    hex = hex:gsub("^0x", ""):gsub("^#", "")
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
    return nil
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function load_config()
    local path = wm.get_config_path()
    local file = io.open(path, "r")
    if not file then return {} end

    local settings = {}
    for line in file:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key, value = line:match("([^=]+)=([^=]+)")
            if key and value then
                settings[key:trim()] = value:trim()
            end
        end
    end
    file:close()
    return settings
end

-- Apply parsed config directly to design tokens
local cfg = load_config()
local t = HyprWin.theme
t.gaps_in = tonumber(cfg.gaps_in) or t.gaps_in
t.gaps_out = tonumber(cfg.gaps_out) or t.gaps_out
t.border_size = tonumber(cfg.border_size) or t.border_size
t.rounding = tonumber(cfg.rounding) or t.rounding

local act_col = parse_hex_color(cfg.active_border_color)
if act_col then t.active_border_color = act_col; t.accent_color = act_col end
local inact_col = parse_hex_color(cfg.inactive_border_color)
if inact_col then t.border_color = inact_col end

HyprWin.layout_mode = cfg.layout_mode or "bsp"
HyprWin.anim_speed = tonumber(cfg.animation_speed) or 0.15

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

local window_rules = {
    float = { "Telegram", "Picture-in-picture", "Calculator", "Картинка в картинке" },
    ignore_classes = { 
        "Chrome_ChildWin_Templ", "HyprWinOverlay", "GhostWindow", 
        "DesktopWindowXamlSource", "MSCTFIME UI", "IME", "CicMarshalWnd",
        "TaskManagerWindow"
    }
}

local function is_tracked(hwnd)
    for i, w in ipairs(HyprWin.windows) do
        if w == hwnd then return i end
    end
    return nil
end

local function should_ignore(hwnd, title, class)
    title = title or ""
    class = class or ""
    for _, pattern in ipairs(window_rules.ignore_classes) do
        if class:find(pattern) then return true end
    end
    for _, pattern in ipairs(window_rules.float) do
        if title:find(pattern) then return true end
    end
    return false
end

HyprWin.retile = function()
    if is_retiling then return end
    is_retiling = true

    local success, err = pcall(function()
        local valid_windows = {}
        for _, hwnd in ipairs(HyprWin.windows) do
            if wm.is_window_visible(hwnd) and not wm.is_topmost(hwnd) then
                table.insert(valid_windows, hwnd)
            end
        end
        HyprWin.windows = valid_windows

        for _, hwnd in ipairs(HyprWin.windows) do
            if not HyprWin.window_workspaces[hwnd] then
                HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            end
        end

        if not HyprWin.workspace_ratios[HyprWin.current_workspace] then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = 0.5
        end

        local active_workspace_windows = {}
        local fullscreen_hwnd = nil

        for _, hwnd in ipairs(HyprWin.windows) do
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            local is_sticky = HyprWin.sticky_windows[hwnd]
            local is_active_ws = (ws == HyprWin.current_workspace)

            if is_active_ws or is_sticky then
                if not wm.is_minimized(hwnd) then
                    if HyprWin.fullscreen_windows[hwnd] then
                        fullscreen_hwnd = hwnd
                    end

                    if not HyprWin.floating_windows[hwnd] then
                        table.insert(active_workspace_windows, hwnd)
                    else
                        local x, y, _, _ = wm.get_window_rect(hwnd)
                        if x < -10000 or y < -10000 then
                            local saved_rect = HyprWin.floating_rects[hwnd]
                            if saved_rect then
                                wm.move_window(hwnd, saved_rect[1], saved_rect[2], saved_rect[3], saved_rect[4])
                            else
                                wm.move_window(hwnd, 150, 150, 1280, 720)
                            end
                        end
                    end
                end
            else
                if HyprWin.floating_windows[hwnd] then
                    local x, y, w, h = wm.get_window_rect(hwnd)
                    if x >= -10000 and y >= -10000 then
                        HyprWin.floating_rects[hwnd] = { x, y, w, h }
                    end
                end
                wm.move_window(hwnd, -32000, -32000, 800, 600)
            end
        end

        local sw, sh = wm.get_screen_size()
        local bar_h = HyprWin.theme.bar_height + 5
        
        local tx, ty = t.gaps_out, bar_h + t.gaps_out
        local tw, th = sw - (t.gaps_out * 2), sh - bar_h - (t.gaps_out * 2)

        if fullscreen_hwnd then
            for _, hwnd in ipairs(active_workspace_windows) do
                if hwnd == fullscreen_hwnd then
                    wm.move_window(hwnd, tx, ty, tw, th)
                else
                    wm.move_window(hwnd, -32000, -32000, 800, 600)
                end
            end
            return
        end

        local n = #active_workspace_windows
        if n == 0 then return end

        local current_ratio = HyprWin.workspace_ratios[HyprWin.current_workspace]

        local function recursive_tile(x, y, w, h, first, last, depth)
            depth = depth or 0
            if first == last then
                wm.move_window(active_workspace_windows[first], x, y, w, h)
                return
            end

            local mid = math.floor((first + last) / 2)
            local ratio = (depth == 0) and current_ratio or 0.5

            if w > h then
                local w1 = math.floor((w - t.gaps_in) * ratio)
                recursive_tile(x, y, w1, h, first, mid, depth + 1)
                recursive_tile(x + w1 + t.gaps_in, y, w - w1 - t.gaps_in, h, mid + 1, last, depth + 1)
            else
                local h1 = math.floor((h - t.gaps_in) * ratio)
                recursive_tile(x, y, w, h1, first, mid, depth + 1)
                recursive_tile(x, y + h1 + t.gaps_in, w, h - h1 - t.gaps_in, mid + 1, last, depth + 1)
            end
        end

        if HyprWin.layout_mode == "bsp" then
            recursive_tile(tx, ty, tw, th, 1, n, 0)
        elseif HyprWin.layout_mode == "master" then
            -- Master-stack implementation fallback (not used globally in BSP default)
        end
    end)

    is_retiling = false
    if not success then
        log("RETILING ERROR: " .. tostring(err))
    end
end

HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
        if not is_tracked(hwnd) and is_valid(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            HyprWin.retile()
        end
        return
    end

    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
        end
        HyprWin.retile()
    end

    if event_type == 0x8001 or event_type == 0x8003 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            if HyprWin.focused_window == hwnd then
                HyprWin.focused_window = nil
            end
            HyprWin.retile()
        end
    end

    if event_type == 0x0016 then
        HyprWin.retile()
    end
end

HyprWin.ui_anims = {
    bar_y = -40,
    launcher_alpha = 0
}

local function lerp(current, target, speed)
    return current + (target - current) * speed
end

HyprWin.on_render = function()
    local time = os.clock()
    
    HyprWin.ui_anims.bar_y = lerp(HyprWin.ui_anims.bar_y, 0, HyprWin.anim_speed)
    HyprWin.ui_anims.launcher_alpha = lerp(HyprWin.ui_anims.launcher_alpha, HyprWin.launcher_active and 1 or 0, HyprWin.anim_speed)

    -- Window Borders drawing directly bound to layout theme tokens
    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        if ws == HyprWin.current_workspace and not wm.is_minimized(hwnd) then
            local x, y, w, h = wm.get_window_rect(hwnd)
            if hwnd == HyprWin.focused_window then
                local glow = 0.1 * math.sin(time * 5)
                local act = t.active_border_color
                ui.draw_rounded_rect(x-3, y-3, w+6, h+6, t.rounding + 4, act[1], act[2], act[3], 0.2 + glow, 8) 
                ui.draw_rounded_rect(x, y, w, h, t.rounding, act[1], act[2], act[3], act[4], t.border_size) 
            end
        end
    end

    topbar.draw(HyprWin.ui_anims.bar_y)
    alttab.draw()
    launcher.draw(HyprWin.ui_anims.launcher_alpha)
end

-- Initial scanning loop
local existing = wm.enumerate_windows()
local filtered = {}
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        table.insert(filtered, hwnd)
        HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
    end
end

local function find_neighbor(dir)
    local focused = HyprWin.focused_window
    if not focused then return nil end

    local fx, fy, fw, fh = wm.get_window_rect(focused)
    local fcx = fx + fw / 2
    local fcy = fy + fh / 2

    local best_hwnd = nil
    local best_dist = math.huge

    for _, hwnd in ipairs(HyprWin.windows) do
        if hwnd ~= focused and not HyprWin.floating_windows[hwnd] then
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            if ws == HyprWin.current_workspace then
                local x, y, w, h = wm.get_window_rect(hwnd)
                local cx = x + w / 2
                local cy = y + h / 2

                local valid = (dir == "left"  and cx < fcx)
                           or (dir == "right" and cx > fcx)
                           or (dir == "up"    and cy < fcy)
                           or (dir == "down"  and cy > fcy)

                if valid then
                    local dist = math.abs(cx - fcx) + math.abs(cy - fcy)
                    if dist < best_dist then
                        best_dist = dist
                        best_hwnd = hwnd
                    end
                end
            end
        end
    end

    return best_hwnd
end

local function focus_direction(dir)
    local target = find_neighbor(dir)
    if target then wm.focus_window(target) end
end

local function swap_direction(dir)
    local focused = HyprWin.focused_window
    local target  = find_neighbor(dir)
    if not focused or not target then return end

    local idx1, idx2 = nil, nil
    for i, hwnd in ipairs(HyprWin.windows) do
        if hwnd == focused then idx1 = i end
        if hwnd == target  then idx2 = i end
    end

    if idx1 and idx2 then
        HyprWin.windows[idx1], HyprWin.windows[idx2] = HyprWin.windows[idx2], HyprWin.windows[idx1]
        HyprWin.retile()
    end
end

HyprWin.on_hotkey = function(id)
    if id >= 101 and id <= 109 then
        local target_ws = id - 100
        if target_ws ~= HyprWin.current_workspace then
            HyprWin.current_workspace = target_ws
            HyprWin.retile()
        end
    elseif id >= 201 and id <= 209 then
        local target_ws = id - 200
        local focused = HyprWin.focused_window
        if focused then
            HyprWin.window_workspaces[focused] = target_ws
            HyprWin.retile()
        end
    elseif id == 301 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.floating_windows[focused] then
                HyprWin.floating_windows[focused] = nil
                HyprWin.sticky_windows[focused] = nil
            else
                HyprWin.floating_windows[focused] = true
            end
            HyprWin.retile()
        end
    elseif id == 302 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.sticky_windows[focused] then
                HyprWin.sticky_windows[focused] = nil
            else
                HyprWin.sticky_windows[focused] = true
                HyprWin.floating_windows[focused] = true
            end
            HyprWin.retile()
        end
    elseif id == 303 then
        local active_hwnd = wm.get_foreground_window()
        if active_hwnd and active_hwnd ~= 0 then
            wm.force_enable_resize(active_hwnd)
            if not is_tracked(active_hwnd) then
                table.insert(HyprWin.windows, active_hwnd)
                HyprWin.window_workspaces[active_hwnd] = HyprWin.current_workspace
            end
            HyprWin.floating_windows[active_hwnd] = nil
            HyprWin.retile()
        end
    elseif id == 304 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.fullscreen_windows[focused] then
                HyprWin.fullscreen_windows[focused] = nil
            else
                HyprWin.fullscreen_windows[focused] = true
            end
            HyprWin.retile()
        end
    elseif id == 305 then
        launcher.toggle()
    elseif id == 306 then
        launcher.commit()
    elseif id == 401 then
        focus_direction("left")
    elseif id == 402 then
        if HyprWin.launcher_active then
            launcher.navigate("down")
        else
            focus_direction("down")
        end
    elseif id == 403 then
        if HyprWin.launcher_active then
            launcher.navigate("up")
        else
            focus_direction("up")
        end
    elseif id == 404 then
        focus_direction("right")
    elseif id == 501 then
        swap_direction("left")
    elseif id == 502 then
        swap_direction("down")
    elseif id == 503 then
        swap_direction("up")
    elseif id == 504 then
        swap_direction("right")
    elseif id == 601 or id == 603 then
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio > 0.15 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio - 0.05
            HyprWin.retile()
        end
    elseif id == 602 or id == 604 then
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio < 0.85 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio + 0.05
            HyprWin.retile()
        end
    end
end

HyprWin.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

HyprWin.windows = filtered
HyprWin.retile()