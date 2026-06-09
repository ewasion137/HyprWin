HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
HyprWin.current_workspace = 1
HyprWin.window_workspaces = {} -- Tracks workspace ID for each hwnd
HyprWin.floating_windows = {}  -- Tracks floating state for each hwnd (boolean)
HyprWin.floating_rects = {}    -- Stores custom geometry {x, y, w, h} for floating windows
HyprWin.sticky_windows = {}    -- Tracks pinned/sticky state (visible on all workspaces)
HyprWin.fullscreen_windows = {} -- Tracks monocle-fullscreen state for each hwnd (boolean)
HyprWin.workspace_ratios = {}  -- Stores split ratio (0.1 - 0.9) for each workspace
local is_retiling = false

-- Helper to check if window still exists and is visible
local function is_valid(hwnd)
    return wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd)
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

-- --- FIXED CODE LOCATOR: retile logic ---
HyprWin.retile = function()
    -- Deep clean the list before every math operation
    local valid_windows = {}
    for _, hwnd in ipairs(HyprWin.windows) do
        -- Keep windows that are visible, not minimized, and not topmost (dynamic filter)
        if wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd) and not wm.is_topmost(hwnd) then
            table.insert(valid_windows, hwnd)
        end
    end
    HyprWin.windows = valid_windows

    -- Ensure every window is assigned to a workspace safely
    for _, hwnd in ipairs(HyprWin.windows) do
        if not HyprWin.window_workspaces[hwnd] then
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
        end
    end

    -- Initialize workspace ratio if not set (default 0.5)
    if not HyprWin.workspace_ratios[HyprWin.current_workspace] then
        HyprWin.workspace_ratios[HyprWin.current_workspace] = 0.5
    end

    -- Filter active workspace, floating, and sticky windows
    local active_workspace_windows = {}
    local fullscreen_hwnd = nil

    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        local is_sticky = HyprWin.sticky_windows[hwnd]
        local is_active_ws = (ws == HyprWin.current_workspace)

        if is_active_ws or is_sticky then
            -- Identify if any active window on this workspace is set to fullscreen (respecting topbar)
            if HyprWin.fullscreen_windows[hwnd] then
                fullscreen_hwnd = hwnd
            end

            if not HyprWin.floating_windows[hwnd] then
                table.insert(active_workspace_windows, hwnd)
            else
                -- Restore floating or sticky window safely
                local x, y, _, _ = wm.get_window_rect(hwnd)
                if x < -10000 or y < -10000 then
                    local saved_rect = HyprWin.floating_rects[hwnd]
                    if saved_rect then
                        wm.move_window(hwnd, saved_rect[1], saved_rect[2], saved_rect[3], saved_rect[4])
                    else
                        -- Fallback center position
                        wm.move_window(hwnd, 150, 150, 1280, 720)
                    end
                end
            end
        else
            -- Save floating window layout before stashing it off-screen
            if HyprWin.floating_windows[hwnd] then
                local x, y, w, h = wm.get_window_rect(hwnd)
                if x >= -10000 and y >= -10000 then
                    HyprWin.floating_rects[hwnd] = { x, y, w, h }
                end
            end
            -- Move off-screen to hide from view without minimizing
            wm.move_window(hwnd, -32000, -32000, 800, 600)
        end
    end

    local sw, sh = wm.get_screen_size()
    local gap = 15
    local bar_h = 35
    
    -- Correct work area
    local tx, ty = gap, bar_h + gap
    local tw, th = sw - (gap * 2), sh - bar_h - (gap * 2)

    -- Handle Monocle Fullscreen (respecting topbar)
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

    -- Recursive BSP splitting (Hyprland dwindle concept)
    local function recursive_tile(x, y, w, h, first, last)
        if first == last then
            wm.move_window(active_workspace_windows[first], x, y, w, h)
            return
        end

        local mid = math.floor((first + last) / 2)

        -- Choose split axis based on aspect ratio
        if w > h then
            -- Split vertically (left and right) using workspace split ratio
            local w1 = math.floor((w - gap) * current_ratio)
            recursive_tile(x, y, w1, h, first, mid)
            recursive_tile(x + w1 + gap, y, w - w1 - gap, h, mid + 1, last)
        else
            -- Split horizontally (top and bottom) using workspace split ratio
            local h1 = math.floor((h - gap) * current_ratio)
            recursive_tile(x, y, w, h1, first, mid)
            recursive_tile(x, y + h1 + gap, w, h - h1 - gap, mid + 1, last)
        end
    end

    recursive_tile(tx, ty, tw, th, 1, n)
end

-- --- FIXED CODE LOCATOR: event dispatcher ---
HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    -- 0x0003: Focus changed
    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
        -- Catch window on focus if we missed its show event
        if not is_tracked(hwnd) and is_valid(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.retile()
        end
        return
    end

    -- 0x8002: Show, 0x0017: Restore
    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.retile()
        end
    end

    -- 0x8001: Destroy, 0x8003: Hide, 0x0016: Minimize
    if event_type == 0x8001 or event_type == 0x8003 or event_type == 0x0016 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            log("Untracked window: " .. hwnd .. " | Remaining: " .. #HyprWin.windows)
            if HyprWin.focused_window == hwnd then
                HyprWin.focused_window = nil
            end
            HyprWin.retile()
        end
    end
end

-- Border rendering with safety checks
HyprWin.on_render = function()
    -- Only draw borders for windows we actually track on the current workspace
    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        if ws == HyprWin.current_workspace then
            local x, y, w, h = wm.get_window_rect(hwnd)
            if w > 0 then
                -- Active window gets a thicker, brighter border
                if hwnd == HyprWin.focused_window then
                    ui.draw_rect(x, y, w, h, 0.7, 0.4, 1.0, 1.0, 3.0) 
                else
                    -- Floating windows get a distinct orange border
                    if HyprWin.floating_windows[hwnd] then
                        ui.draw_rect(x, y, w, h, 0.9, 0.6, 0.2, 0.8, 1.5)
                    else
                        ui.draw_rect(x, y, w, h, 0.2, 0.2, 0.2, 0.8, 1.0)
                    end
                end
            end
        end
    end
    
    -- Simple Top Bar
    local sw, _ = wm.get_screen_size()
    ui.fill_rect(0, 0, sw, 35, 0.02, 0.02, 0.02, 0.9)
    ui.fill_rect(0, 35, sw, 2, 0.7, 0.4, 1.0, 1.0)

    -- Render workspace indicators
    local ind_w = 20
    local ind_h = 14
    local start_x = 15
    local start_y = 10
    local gap_x = 8

    for i = 1, 9 do
        local x = start_x + (i - 1) * (ind_w + gap_x)
        if i == HyprWin.current_workspace then
            -- Active workspace in bright purple
            ui.fill_rect(x, start_y, ind_w, ind_h, 0.7, 0.4, 1.0, 1.0)
        else
            -- Inactive workspaces in dark gray
            ui.fill_rect(x, start_y, ind_w, ind_h, 0.15, 0.15, 0.15, 0.8)
        end
    end
end
-- Initial scan
local existing = wm.enumerate_windows()
local filtered = {}
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        table.insert(filtered, hwnd)
    end
end

local function focus_direction(dir)
    local focused = HyprWin.focused_window
    if not focused then return end
    
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
                
                local is_in_dir = false
                if dir == "left" and cx < fcx then
                    is_in_dir = true
                elseif dir == "right" and cx > fcx then
                    is_in_dir = true
                elseif dir == "up" and cy < fcy then
                    is_in_dir = true
                elseif dir == "down" and cy > fcy then
                    is_in_dir = true
                end
                
                if is_in_dir then
                    -- Calculate Manhattan distance between windows
                    local dist = math.abs(cx - fcx) + math.abs(cy - fcy)
                    if dist < best_dist then
                        best_dist = dist
                        best_hwnd = hwnd
                    end
                end
            end
        end
    end
    
    if best_hwnd then
        wm.focus_window(best_hwnd)
    end
end

local function swap_direction(dir)
    local focused = HyprWin.focused_window
    if not focused then return end
    
    local fx, fy, fw, fh = wm.get_window_rect(focused)
    local fcx = fx + fw / 2
    local fcy = fy + fh / 2
    
    local target_hwnd = nil
    local best_dist = math.huge
    
    for _, hwnd in ipairs(HyprWin.windows) do
        if hwnd ~= focused and not HyprWin.floating_windows[hwnd] then
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            if ws == HyprWin.current_workspace then
                local x, y, w, h = wm.get_window_rect(hwnd)
                local cx = x + w / 2
                local cy = y + h / 2
                
                local is_in_dir = false
                if dir == "left" and cx < fcx then
                    is_in_dir = true
                elseif dir == "right" and cx > fcx then
                    is_in_dir = true
                elseif dir == "up" and cy < fcy then
                    is_in_dir = true
                elseif dir == "down" and cy > fcy then
                    is_in_dir = true
                end
                
                if is_in_dir then
                    local dist = math.abs(cx - fcx) + math.abs(cy - fcy)
                    if dist < best_dist then
                        best_dist = dist
                        target_hwnd = hwnd
                    end
                end
            end
        end
    end
    
    if target_hwnd then
        local idx1, idx2 = nil, nil
        for i, hwnd in ipairs(HyprWin.windows) do
            if hwnd == focused then idx1 = i end
            if hwnd == target_hwnd then idx2 = i end
        end
        
        if idx1 and idx2 then
            HyprWin.windows[idx1], HyprWin.windows[idx2] = HyprWin.windows[idx2], HyprWin.windows[idx1]
            HyprWin.retile()
        end
    end
end

HyprWin.on_hotkey = function(id)
    if id >= 101 and id <= 109 then
        -- Switch Workspace (Alt + 1..9)
        local target_ws = id - 100
        if target_ws ~= HyprWin.current_workspace then
            HyprWin.current_workspace = target_ws
            log("Switched to Workspace " .. target_ws)
            HyprWin.retile()
        end
    elseif id >= 201 and id <= 209 then
        -- Move Window to Workspace (Alt + Shift + 1..9)
        local target_ws = id - 200
        local focused = HyprWin.focused_window
        if focused then
            HyprWin.window_workspaces[focused] = target_ws
            log("Moved window " .. focused .. " to Workspace " .. target_ws)
            HyprWin.retile()
        end
    elseif id == 301 then
        -- Toggle Floating State (Alt + F)
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.floating_windows[focused] then
                HyprWin.floating_windows[focused] = nil
                HyprWin.sticky_windows[focused] = nil -- Unfloated windows cannot be sticky
                log("Window " .. focused .. " is now Tiled")
            else
                HyprWin.floating_windows[focused] = true
                log("Window " .. focused .. " is now Floating")
            end
            HyprWin.retile()
        end
    elseif id == 302 then
        -- Toggle Sticky State (Alt + P)
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.sticky_windows[focused] then
                HyprWin.sticky_windows[focused] = nil
                log("Window " .. focused .. " is no longer Sticky")
            else
                HyprWin.sticky_windows[focused] = true
                HyprWin.floating_windows[focused] = true -- Pinning requires floating state
                log("Window " .. focused .. " is now Sticky (Pinned to all workspaces)")
            end
            HyprWin.retile()
        end
    elseif id == 303 then
        -- Force Tile (Alt + T)
        local active_hwnd = wm.get_foreground_window()
        if active_hwnd and active_hwnd ~= 0 then
            wm.force_enable_resize(active_hwnd)
            if not is_tracked(active_hwnd) then
                table.insert(HyprWin.windows, active_hwnd)
            end
            HyprWin.floating_windows[active_hwnd] = nil
            HyprWin.window_workspaces[active_hwnd] = HyprWin.current_workspace
            log("Force tiled window: " .. active_hwnd)
            HyprWin.retile()
        end
    elseif id == 401 then
        focus_direction("left")
    elseif id == 402 then
        focus_direction("up")
    elseif id == 403 then
        focus_direction("right")
    elseif id == 404 then
        focus_direction("down")
    elseif id == 501 then
        swap_direction("left")
    elseif id == 502 then
        swap_direction("up")
    elseif id == 503 then
        swap_direction("right")
    elseif id == 504 then
        swap_direction("down")
    end
end

HyprWin.windows = filtered
HyprWin.retile()