-- --- FIXED CODE LOCATOR: scripts/ui/topbar.lua ---
local topbar = {}

local FONT        = "Segoe UI Variable"
local ICON_FONT   = "Segoe MDL2 Assets"
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

    -- Workspace indicators with modern monitor symbols
    for i = 1, 9 do
        local is_active = (i == HyprWin.current_workspace)
        local has_wins  = (ws_window_count(i) > 0)

        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        local wy = by + (BAR_HEIGHT - WS_BOX_H) / 2

        if is_active then
            -- Deep purple fill for active workspace
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, 4, 0.7, 0.4, 1.0, 1.0)
            ui.draw_text(tostring(i), wx + 5, wy + 1, 11, 1, 1, 1, 1, FONT)
        elseif has_wins then
            -- Glassmorphic outline with a tiny screen icon for occupied workspaces
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, 4, 0.4, 0.25, 0.65, 0.25)
            ui.draw_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, 4, 0.7, 0.4, 1.0, 0.40, 1.0)
            ui.draw_text("\u{E7F4}", wx + 3, wy + 2, 9, 0.7, 0.4, 1.0, 0.85, ICON_FONT)
        else
            -- Plain dark fill for empty workspaces
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, 4, 0.12, 0.12, 0.15, 0.70)
        end
    end

    local now = os.clock()
    if now - HyprWin.system_stats.last_update > 1.0 then
        HyprWin.system_stats.cpu = math.floor(wm.get_cpu_usage())
        HyprWin.system_stats.ram = math.floor(wm.get_ram_usage())
        HyprWin.system_stats.last_update = now
    end

    local cpu      = HyprWin.system_stats.cpu
    local ram      = HyprWin.system_stats.ram
    local time_str = get_time_string()
    local ram_str  = string.format("%d%%", ram)
    local cpu_str  = string.format("%d%%", cpu)

    local text_y   = by + (BAR_HEIGHT - 12) / 2 - 1
    local icon_w   = 14
    local spacing  = 16

    -- Layout alignment engine (Right-to-Left)
    local cur_x = bar_x + bar_w - 20

    -- 1. Draw Time block
    local time_w = ui.measure_text(time_str, 12, FONT)
    cur_x = cur_x - time_w
    ui.draw_text(time_str, cur_x, text_y, 12, 0.85, 0.85, 0.95, 0.90, FONT)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E121}", cur_x, text_y + 1, 11, 0.7, 0.4, 1.0, 0.90, ICON_FONT)

    -- 2. Draw RAM block
    local ram_w = ui.measure_text(ram_str, 12, FONT)
    cur_x = cur_x - spacing - ram_w
    ui.draw_text(ram_str, cur_x, text_y, 12, 0.85, 0.85, 0.95, 0.90, FONT)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E9A1}", cur_x, text_y + 1, 11, 0.7, 0.4, 1.0, 0.90, ICON_FONT)

    -- 3. Draw CPU block
    local cpu_w = ui.measure_text(cpu_str, 12, FONT)
    cur_x = cur_x - spacing - cpu_w
    ui.draw_text(cpu_str, cur_x, text_y, 12, 0.85, 0.85, 0.95, 0.90, FONT)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E9D9}", cur_x, text_y + 1, 11, 0.7, 0.4, 1.0, 0.90, ICON_FONT)

    -- Focused window title (center)
    if HyprWin.focused_window and HyprWin.focused_window_title ~= "" then
        local title   = HyprWin.focused_window_title
        local title_w = ui.measure_text(title, 12, FONT)
        local title_x = bar_x + (bar_w - title_w) / 2
        ui.draw_text(title, title_x, text_y, 12, 0.85, 0.85, 0.95, 0.80, FONT)
    end
end

return topbar