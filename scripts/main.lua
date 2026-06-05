HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
HyprWin.current_workspace = 1
HyprWin.window_workspaces = {} -- Tracks workspace ID for each hwnd
HyprWin.floating_windows = {}  -- Tracks floating state for each hwnd (boolean)
local is_retiling = false

-- Helper to check if window still exists and is visible
local function is_valid(hwnd)
    return wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd)
end

local window_rules = {
    float = { "Telegram", "Picture-in-picture", "Calculator", "Картинка в картинке" },
    ignore_classes = { "Chrome_ChildWin_Templ", "HyprWinOverlay", "GhostWindow" }
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
        -- Only keep windows that are actually visible and NOT minimized
        if wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd) then
            table.insert(valid_windows, hwnd)
        end
    end
    HyprWin.windows = valid_windows

    local n = #HyprWin.windows
    if n == 0 then return end

    local sw, sh = wm.get_screen_size()
    local gap = 15
    local bar_h = 35
    
    -- Correct work area
    local tx, ty = gap, bar_h + gap
    local tw, th = sw - (gap * 2), sh - bar_h - (gap * 2)

    -- Recursive BSP splitting (Hyprland dwindle concept)
    local function recursive_tile(x, y, w, h, first, last)
        if first == last then
            wm.move_window(HyprWin.windows[first], x, y, w, h)
            return
        end

        local mid = math.floor((first + last) / 2)

        -- Choose split axis based on aspect ratio
        if w > h then
            -- Split vertically (left and right)
            local w1 = math.floor((w - gap) / 2)
            recursive_tile(x, y, w1, h, first, mid)
            recursive_tile(x + w1 + gap, y, w - w1 - gap, h, mid + 1, last)
        else
            -- Split horizontally (top and bottom)
            local h1 = math.floor((h - gap) / 2)
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
    -- Only draw borders for windows we actually track
    for _, hwnd in ipairs(HyprWin.windows) do
        local x, y, w, h = wm.get_window_rect(hwnd)
        if w > 0 then
            -- Active window gets a thicker, brighter border
            if hwnd == HyprWin.focused_window then
                ui.draw_rect(x, y, w, h, 0.7, 0.4, 1.0, 1.0, 3.0) 
            else
                ui.draw_rect(x, y, w, h, 0.2, 0.2, 0.2, 0.8, 1.0)
            end
        end
    end
    
    -- Simple Top Bar
    local sw, _ = wm.get_screen_size()
    ui.fill_rect(0, 0, sw, 30, 0.02, 0.02, 0.02, 0.9)
    ui.fill_rect(0, 30, sw, 2, 0.7, 0.4, 1.0, 1.0)
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
HyprWin.windows = filtered
HyprWin.retile()