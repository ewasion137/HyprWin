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
    -- Filter dead handles
    local active = {}
    for _, h in ipairs(HyprWin.windows) do
        if wm.is_window_visible(h) and not wm.is_minimized(h) then
            table.insert(active, h)
        end
    end
    HyprWin.windows = active

    local n = #HyprWin.windows
    if n == 0 then return end

    local sw, sh = wm.get_screen_size()
    local gap = 10
    local bar_h = 35
    
    -- Calculation area
    local tx = gap
    local ty = bar_h + gap
    local tw = sw - (gap * 2)
    local th = sh - bar_h - (gap * 2)

    if n == 1 then
        wm.move_window(HyprWin.windows[1], tx, ty, tw, th)
    else
        -- Mathematical split: Master gets 50%, Stack gets 50%
        local m_w = (tw - gap) / 2
        local s_w = tw - m_w - gap
        local s_x = tx + m_w + gap

        -- Master window
        wm.move_window(HyprWin.windows[1], tx, ty, m_w, th)

        -- Stack windows split height equally
        local s_h = (th - (gap * (n - 2))) / (n - 1)
        for i = 2, n do
            local y_off = ty + ((i - 2) * (s_h + gap))
            wm.move_window(HyprWin.windows[i], s_x, y_off, s_w, s_h)
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