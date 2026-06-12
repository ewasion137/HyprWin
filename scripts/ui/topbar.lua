local topbar = {}

local FONT        = "Segoe UI Variable"
local BAR_HEIGHT  = 30
local BAR_MARGIN  = 5
local WS_BOX_W    = 18
local WS_BOX_H    = 16
local WS_SPACING  = 25
local WS_OFFSET_X = 15

-- Returns how many tracked windows belong to a given workspace
local function ws_window_count(ws_id)
    local count = 0
    for _, hwnd in ipairs(HyprWin.windows) do
        if HyprWin.window_workspaces[hwnd] == ws_id then
            count = count + 1
        end
    end
    return count
end

-- Formats seconds-since-epoch into HH:MM string using OS clock
local function get_time_string()
    return os.date("%H:%M")
end

function topbar.draw(anim_y)
    local sw, _ = wm.get_screen_size()

    local bar_w = sw - 40
    local bar_x = 20
    local by    = anim_y + BAR_MARGIN

    -- Bar background and border
    ui.fill_rounded_rect(bar_x, by, bar_w, BAR_HEIGHT, 10, 0.02, 0.02, 0.03, 0.90)
    ui.draw_rounded_rect(bar_x, by, bar_w, BAR_HEIGHT, 10, 0.7, 0.4, 1.0, 0.30, 1.5)

    -- Workspace indicators
    for i = 1, 9 do
        local is_active = (i == HyprWin.current_workspace)
        local has_wins  = (ws_window_count(i) > 0)

        local cr, cg, cb, ca
        if is_active then
            cr, cg, cb, ca = 0.7, 0.4, 1.0, 1.0
        elseif has_wins then
            cr, cg, cb, ca = 0.4, 0.25, 0.65, 0.85
        else
            cr, cg, cb, ca = 0.15, 0.15, 0.20, 0.70
        end

        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        local wy = by + (BAR_HEIGHT - WS_BOX_H) / 2
        ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, 4, cr, cg, cb, ca)

        -- Show number only on the active workspace to keep it clean
        if is_active then
            ui.draw_text(tostring(i), wx + 5, wy + 1, 11, 1, 1, 1, 1, FONT)
        end
    end

    -- Right-side system stats (clock, CPU, RAM)
    local cpu  = math.floor(wm.get_cpu_usage())
    local ram  = math.floor(wm.get_ram_usage())
    local time = get_time_string()

    local stats = string.format("CPU %d%%  RAM %d%%  %s", cpu, ram, time)

    -- Measure and right-align the stats string
    local text_w  = ui.measure_text(stats, 12, FONT)
    local text_x  = bar_x + bar_w - text_w - 15
    local text_y  = by + (BAR_HEIGHT - 12) / 2 - 1

    ui.draw_text(stats, text_x, text_y, 12, 0.75, 0.75, 0.85, 0.90, FONT)

    -- Focused window title (center)
    if HyprWin.focused_window then
        local title   = wm.get_window_title(HyprWin.focused_window)
        local title_w = ui.measure_text(title, 12, FONT)
        local title_x = bar_x + (bar_w - title_w) / 2
        ui.draw_text(title, title_x, text_y, 12, 0.85, 0.85, 0.95, 0.80, FONT)
    end
end

return topbar
