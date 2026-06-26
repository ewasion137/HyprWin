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

-- Trim helper (Must be defined first for other modules to use it on load)
function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Filter list to ignore background processes and system overlays
local ignored_classes = {
    "WorkerW", "Progman", "Shell_TrayWnd", "HyprWinOverlay",
    "Chrome_ChildWin_Templ", "GhostWindow", "DesktopWindowXamlSource", 
    "MSCTFIME UI", "IME", "CicMarshalWnd", "TaskManagerWindow"
}

-- Safe window tracking filter function
function should_ignore(hwnd, title, class)
    if title == "" and class == "" then return true end
    for _, ic in ipairs(ignored_classes) do
        if class == ic then return true end
    end
    return false
end

package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua;./scripts/?/init.lua"

-- Dynamic path mapping for multi-file user configs
local user_path = wm.get_config_path()
local user_dir = user_path:match("(.*[/\\])")
if user_dir then
    package.path = package.path .. ";" .. user_dir .. "?.lua;" .. user_dir .. "?/init.lua"
end

local topbar = require("topbar")
local alttab = require("alttab")
local launcher = require("launcher")
local hl_shim = require("hl_shim")

-- Run the user's entry point config file
local success, err = pcall(dofile, user_path)
if not success then
    log("CONFIG ERROR: " .. tostring(err))
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

local function is_tracked(hwnd)
    for i, w in ipairs(HyprWin.windows) do
        if w == hwnd then return i end
    end
    return nil
end

-- Solve Bezier curves using binary search approximation
local function solve_bezier(p1, p2, t)
    local x1, y1 = p1[1], p1[2]
    local x2, y2 = p2[1], p2[2]
    
    local function get_pt(n1, n2, t_val)
        return 3 * (1 - t_val)^2 * t_val * n1 + 3 * (1 - t_val) * t_val^2 * n2 + t_val^3
    end
    
    local low, high = 0.0, 1.0
    local guess = t
    for i = 1, 8 do
        local current_x = get_pt(x1, x2, guess)
        if math.abs(current_x - t) < 0.001 then
            break
        elseif current_x < t then
            low = guess
        else
            high = guess
        end
        guess = (low + high) / 2
    end
    
    return get_pt(y1, y2, guess)
end

-- Initialize state engines for smooth curves
HyprWin.anim_states = {
    bar = { current = -40, start_val = -40, target = -40, start_time = 0, duration = 0.35, curve = "easeOutQuint" },
    launcher = { current = 0, start_val = 0, target = 0, start_time = 0, duration = 0.28, curve = "md3_decel" }
}

-- Calculate animated progress on the fly using active configuration curves
local function update_animation(name, target_val)
    local anim = HyprWin.anim_states[name]
    if anim.target ~= target_val then
        anim.start_val = anim.current
        anim.target = target_val
        anim.start_time = os.clock()
    end
    
    local elapsed = os.clock() - anim.start_time
    local progress = math.min(1.0, elapsed / anim.duration)
    
    -- Default ease-out curve fallback
    local p1, p2 = { 0.25, 0.1 }, { 0.25, 1.0 }
    if anim.curve and HyprWin.curves and HyprWin.curves[anim.curve] then
        local curve = HyprWin.curves[anim.curve]
        if curve.type == "bezier" and curve.points then
            p1, p2 = curve.points[1], curve.points[2]
        end
    end
    
    local solved = solve_bezier(p1, p2, progress)
    anim.current = anim.start_val + (anim.target - anim.start_val) * solved
    return anim.current
end

-- Apply advanced sizing and placement window rules
local function apply_window_rules(hwnd, title, class)
    if not HyprWin.window_rules then return end
    
    -- Simple flat float match
    local should_float = false
    for _, pattern in ipairs(HyprWin.window_rules.float or {}) do
        if class:match(pattern) or title:match(pattern) then
            should_float = true
            break
        end
    end
    
    if should_float then
        HyprWin.floating_windows[hwnd] = true
        local x, y, w, h = wm.get_window_rect(hwnd)
        HyprWin.floating_rects[hwnd] = { x, y, w, h }
    end

    -- Evaluate advanced rules with screen size math expressions (like monitor_w * 0.48)
    for _, rule in ipairs(HyprWin.window_rules.rules_list or {}) do
        local m_class = rule.match and rule.match.class
        local m_title = rule.match and rule.match.title
        
        local is_match = false
        if m_class and class:match(m_class) then is_match = true end
        if m_title and title:match(m_title) then is_match = true end
        
        if is_match then
            if rule.float then
                HyprWin.floating_windows[hwnd] = true
            end
            
            if rule.size then
                local sw, sh = wm.get_screen_size()
                local target_w = sw * 0.48
                local target_h = sh * 0.50
                
                -- Parse expressions dynamically
                if type(rule.size[1]) == "string" then
                    local expr = rule.size[1]:gsub("monitor_w", tostring(sw))
                    target_w = load("return " .. expr)() or target_w
                else
                    target_w = rule.size[1]
                end
                
                if type(rule.size[2]) == "string" then
                    local expr = rule.size[2]:gsub("monitor_h", tostring(sh))
                    target_h = load("return " .. expr)() or target_h
                else
                    target_h = rule.size[2]
                end
                
                local rx, ry = math.floor((sw - target_w)/2), math.floor((sh - target_h)/2)
                if rule.move then
                    rx = tonumber(rule.move[1]) or rx
                    ry = tonumber(rule.move[2]) or ry
                end
                
                HyprWin.floating_rects[hwnd] = { rx, ry, target_w, target_h }
                wm.move_window(hwnd, rx, ry, target_w, target_h)
            end
        end
    end
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
            local is_special = (ws == HyprWin.active_special_workspace) -- Check if on active scratchpad

            if is_active_ws or is_sticky or is_special then
                if not wm.is_minimized(hwnd) then
                    if HyprWin.fullscreen_windows[hwnd] then
                        fullscreen_hwnd = hwnd
                    end

                    -- Windows stashed in the scratchpad are forced to float
                    if is_special then
                        HyprWin.floating_windows[hwnd] = true
                    end

                    if not HyprWin.floating_windows[hwnd] then
                        table.insert(active_workspace_windows, hwnd)
                    else
                        -- Restore floating/sticky/special window safely
                        local rect = HyprWin.window_rects[hwnd]
                        if (rect and (rect[1] < -10000 or rect[2] < -10000)) or is_special then
                            local saved = HyprWin.floating_rects[hwnd]
                            if is_special and not saved then
                                -- Center scratchpad window with 70% screen scale layout
                                local sw, sh = wm.get_screen_size()
                                saved = { math.floor(sw * 0.15), math.floor(sh * 0.15), math.floor(sw * 0.70), math.floor(sh * 0.70) }
                                HyprWin.floating_rects[hwnd] = saved
                            end
                            saved = saved or { 150, 150, 1280, 720 }
                            wm.move_window(hwnd, saved[1], saved[2], saved[3], saved[4])
                            HyprWin.window_rects[hwnd] = saved
                        end
                    end
                end
            else
                -- Save current geometry before stashing if the window is floating
                if HyprWin.floating_windows[hwnd] then
                    local rect = HyprWin.window_rects[hwnd]
                    if rect and rect[1] >= -10000 and rect[2] >= -10000 then
                        HyprWin.floating_rects[hwnd] = rect
                    end
                end
                -- Move window off-screen to stash
                wm.move_window(hwnd, -32000, -32000, 800, 600)
                HyprWin.window_rects[hwnd] = { -32000, -32000, 800, 600 }
            end
        end

        local sw, sh = wm.get_screen_size()
        local t = HyprWin.theme
        local bar_h = t.bar_height + 5
        
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

        local active_layout = HyprWin.workspace_rules[HyprWin.current_workspace] or HyprWin.layout_mode

        if active_layout == "bsp" then
            recursive_tile(tx, ty, tw, th, 1, n, 0)
        elseif active_layout == "master" then
            get_master_tiles(tx, ty, tw, th, active_workspace_windows)
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
            local x, y, w, h = wm.get_window_rect(hwnd)
            HyprWin.original_rects[hwnd] = { x, y, w, h }

            table.insert(HyprWin.windows, hwnd)
            local ws = HyprWin.current_workspace
            HyprWin.window_workspaces[hwnd] = ws
            
            -- Trigger rules parser!
            apply_window_rules(hwnd, title, class)
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
    local t = HyprWin.theme

    -- Evaluate math Bezier curves configured in your Linux theme files
    local bar_y = update_animation("bar", 0)
    local launcher_alpha = update_animation("launcher", HyprWin.launcher_active and 1 or 0)
    
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
        apply_window_rules(hwnd, title, class)
    end
end

function find_neighbor(dir)
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

function focus_direction(dir)
    local target = find_neighbor(dir)
    if target then wm.focus_window(target) end
end

function swap_direction(dir)
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

-- Fallback hotkey registration for legacy hardcoded bindings
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