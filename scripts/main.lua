-- scripts/main.lua

HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil

-- Basic Master/Stack layout recalculation
HyprWin.retile = function()
    local count = #HyprWin.windows
    log("Retile starting. Total windows in layout: " .. count)
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()
    local gap = 10 -- Padding between windows

    if count == 1 then
        log("Retiling 1 window: hwnd = " .. HyprWin.windows[1] .. " -> full screen")
        wm.move_window(HyprWin.windows[1], gap, gap, sw - (gap * 2), sh - (gap * 2))
    else
        local master_w = sw // 2
        local half_gap = gap // 2
        log("Retiling Master: hwnd = " .. HyprWin.windows[1] .. " -> x: " .. gap .. ", y: " .. gap .. ", w: " .. (master_w - gap - half_gap) .. ", h: " .. (sh - gap * 2))
        wm.move_window(HyprWin.windows[1], gap, gap, master_w - gap - half_gap, sh - (gap * 2))

        local stack_count = count - 1
        local stack_h = (sh - gap) // stack_count
        local stack_x = master_w + half_gap
        
        for i = 2, count do
            local y_offset = gap + ((i - 2) * stack_h)
            local current_h = stack_h - gap
            log("Retiling Stack [" .. i .. "]: hwnd = " .. HyprWin.windows[i] .. " -> x: " .. stack_x .. ", y: " .. y_offset .. ", w: " .. (sw - stack_x - gap) .. ", h: " .. current_h)
            wm.move_window(HyprWin.windows[i], stack_x, y_offset, sw - stack_x - gap, current_h)
        end
    end
end

local function is_tracked(hwnd)
    for i, w in ipairs(HyprWin.windows) do
        if w == hwnd then return true, i end
    end
    return false, nil
end

-- Dispatcher called from C++
HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    
    -- Filter out junk
    if class == "Chrome_ChildWin_Templ" or class:find("Tip") or class:find("Menu") or class == "HyprWinOverlay" then
        return
    end

    -- Capture: Use ONLY EVENT_OBJECT_SHOW (0x8002) for new windows
    -- Use EVENT_SYSTEM_MINIMIZEEND (0x0017) for restored windows
    if event_type == 0x8002 or event_type == 0x0017 then
        local tracked, _ = is_tracked(hwnd)
        if title ~= "" and title ~= "Program Manager" and not tracked then
            log("Tracking window: [" .. title .. "] HWND: " .. hwnd)
            table.insert(HyprWin.windows, hwnd)
            HyprWin.retile()
        end
    end

    -- Release: EVENT_OBJECT_DESTROY (0x8001) or EVENT_SYSTEM_MINIMIZESTART (0x0016)
    -- Ignore EVENT_OBJECT_HIDE (0x8003) as it fires too often for background apps
    if event_type == 0x8001 or event_type == 0x0016 then
        local tracked, index = is_tracked(hwnd)
        if tracked then
            log("Untracking window: HWND: " .. hwnd)
            table.remove(HyprWin.windows, index)
            if HyprWin.focused_window == hwnd then HyprWin.focused_window = nil end
            HyprWin.retile()
        end
    end

    -- Focus
    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
    end
end

HyprWin.on_render = function()
    -- Draw borders around tracked windows
    for _, hwnd in ipairs(HyprWin.windows) do
        -- Only draw border if window is actually visible and not minimized
        if wm.is_window_visible(hwnd) and not wm.is_minimized(hwnd) then
            local x, y, w, h = wm.get_window_rect(hwnd)
            
            -- Check if we successfully got rect
            if w > 0 and h > 0 then
                if hwnd == HyprWin.focused_window then
                    -- Active window border (Red)
                    ui.draw_rect(x - 2, y - 2, w + 4, h + 4, 1.0, 0.2, 0.2, 1.0, 3.0)
                else
                    -- Inactive window border (Gray)
                    ui.draw_rect(x - 2, y - 2, w + 4, h + 4, 0.5, 0.5, 0.5, 0.8, 2.0)
                end
            end
        end
    end
end

-- On startup, scan for already open windows
local existing = wm.enumerate_windows()
for _, hwnd in ipairs(existing) do
    local class = wm.get_class_name(hwnd)
    -- Ignore known system junk and our own overlay window
    if not (class == "Chrome_ChildWin_Templ" or class:find("Tip") or class:find("Menu") or class == "HyprWinOverlay") then
        log("Tracking existing window on startup: Class: " .. class)
        table.insert(HyprWin.windows, hwnd)
    end
end
HyprWin.retile()

log("HyprWin: Tiling engine and renderer ready.")