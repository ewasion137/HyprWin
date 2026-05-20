HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
local is_retiling = false

-- Helper to check if window still exists and is visible
local function is_valid(hwnd)
    return wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd)
end

local window_rules = {
    float = { "Telegram", "Picture-in-picture", "Calculator", "Картинка в картинке" },
    ignore_classes = { "Chrome_ChildWin_Templ", "HyprWinOverlay", "GhostWindow" }
}

local function should_ignore(hwnd, title, class)
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
    local active_windows = {}
    for _, hwnd in ipairs(HyprWin.windows) do
        local title = "" -- You might want to bind GetWindowText to wm table for better Lua access
        -- For now, we use existing list, but let's filter small windows
        if is_valid(hwnd) then
            table.insert(active_windows, hwnd)
        end
    end
    HyprWin.windows = active_windows

    local count = #HyprWin.windows
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()
    local bar_h = 35
    local gap = 15 -- More gap = more Hyprland aesthetics
    
    -- Master-Stack Logic (Inspired by Hyprland/dwms)
    if count == 1 then
        wm.move_window(HyprWin.windows[1], gap, bar_h + gap, sw - (gap * 2), sh - bar_h - (gap * 2))
    else
        -- Master (Left 60%)
        local master_width = math.floor(sw * 0.6)
        wm.move_window(HyprWin.windows[1], gap, bar_h + gap, master_width - (gap * 1.5), sh - bar_h - (gap * 2))

        -- Stack (Right 40%)
        local stack_x = master_width + (gap * 0.5)
        local stack_width = sw - stack_x - gap
        local total_stack_height = sh - bar_h - (gap * 2)
        local individual_stack_height = (total_stack_height - (gap * (count - 2))) / (count - 1)

        for i = 2, count do
            local y_pos = bar_h + gap + ((i - 2) * (individual_stack_height + gap))
            wm.move_window(HyprWin.windows[i], stack_x, y_pos, stack_width, individual_stack_height)
        end
    end
end

-- --- FIXED CODE LOCATOR: event dispatcher ---
HyprWin.dispatch_event = function(event_type, hwnd, title)
    -- 0x8002: Show, 0x0017: Restore
    if event_type == 0x8002 or event_type == 0x0017 then
        local found = false
        for _, h in ipairs(HyprWin.windows) do if h == hwnd then found = true break end end
        
        if not found and title ~= "" then
            -- Small delay to let Windows finish window creation
            log("Capturing: " .. title)
            table.insert(HyprWin.windows, hwnd)
            HyprWin.retile()
        end
    end

    -- 0x8001: Destroy, 0x8003: Hide, 0x0016: Minimize
    if event_type == 0x8001 or event_type == 0x8003 or event_type == 0x0016 then
        for i, h in ipairs(HyprWin.windows) do
            if h == hwnd then
                log("Releasing window handle")
                table.remove(HyprWin.windows, i)
                HyprWin.retile()
                break
            end
        end
    end

    -- 0x0003: Foreground Change
    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
    end
end

-- Border rendering with safety checks
HyprWin.on_render = function()
    for _, hwnd in ipairs(HyprWin.windows) do
        if is_valid(hwnd) then
            local x, y, w, h = wm.get_window_rect(hwnd)
            if w > 0 then
                if hwnd == HyprWin.focused_window then
                    ui.draw_rect(x, y, w, h, 1.0, 0.3, 0.3, 1.0, 3.0) -- Active: Red
                else
                    ui.draw_rect(x, y, w, h, 0.2, 0.2, 0.2, 0.5, 1.0) -- Inactive: Dark
                end
            end
        end
    end
end

-- Initial scan
local existing = wm.enumerate_windows()
HyprWin.windows = existing
HyprWin.retile()