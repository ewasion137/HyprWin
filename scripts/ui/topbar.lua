-- scripts/ui/topbar.lua
local topbar = {}
local cc = require("control_center")

-- Configuration tokens
local BAR_MARGIN  = 8
local WS_W        = 24
local WS_H        = 18
local WS_SPACING  = 30
local WS_OFFSET_X = 45 -- Adjusted for Start icon

-- Cache for performance
local last_cpu = 0
local last_ram = 0
local last_stat_update = 0
local last_frame_time = os.clock()

local function ws_window_count(ws_id)
    local count = 0
    for _, hwnd in ipairs(HyprWin.windows) do
        if HyprWin.window_workspaces[hwnd] == ws_id then count = count + 1 end
    end
    return count
end

function topbar.draw(anim_y)
    -- --- 1. INITIALIZATION & GEOMETRY ---
    local sw, _ = wm.get_screen_size()
    local t = HyprWin.theme
    local by = anim_y + BAR_MARGIN
    local bar_w = sw - 32
    local bar_x = 16
    
    -- Common vertical centering for text/icons
    local text_y = by + (t.bar_height - 12) / 2
    
    -- Delta time for animations
    local current_time = os.clock()
    local dt = current_time - last_frame_time
    last_frame_time = current_time

    -- --- 2. BACKGROUND ---
    ui.fill_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4])
    ui.draw_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.2, 1)

    -- --- 3. START BUTTON ---
    local start_icon_x = bar_x + 12
    ui.draw_text("\u{E721}", start_icon_x, text_y + 1, 13, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.icon_font_family)

    -- --- 4. WORKSPACES (PILL STYLE) ---
    for i = 1, 7 do
        local is_active = (i == HyprWin.current_workspace)
        local has_wins  = (ws_window_count(i) > 0)

        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        local wy = by + (t.bar_height - WS_H) / 2

        if is_active then
            ui.fill_rounded_rect(wx - 4, wy, WS_W + 8, WS_H, WS_H/2, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1.0)
            ui.draw_text(tostring(i), wx + 6, wy + 2, 11, 0, 0, 0, 1, t.font_family)
        elseif has_wins then
            ui.fill_rounded_rect(wx, wy, WS_W, WS_H, WS_H/2, t.text_color[1], t.text_color[2], t.text_color[3], 0.2)
            ui.draw_text(tostring(i), wx + 7, wy + 2, 10, t.text_color[1], t.text_color[2], t.text_color[3], 0.9, t.font_family)
        else
            ui.fill_rounded_rect(wx + 8, wy + 6, 6, 6, 3, t.text_dim[1], t.text_dim[2], t.text_dim[3], 0.4)
        end
    end

    -- --- 5. CENTER SECTION: WINDOW TITLE ---
    if HyprWin.focused_window then
        local title = wm.get_window_title(HyprWin.focused_window)
        if title:len() > 40 then title = title:sub(1, 37) .. "..." end
        local title_w = ui.measure_text(title, 11, t.font_family)
        ui.draw_text(title, bar_x + (bar_w - title_w) / 2, text_y, 11, t.text_color[1], t.text_color[2], t.text_color[3], 0.7, t.font_family)
    end

    -- --- 6. RIGHT SECTION: SYSTEM STATS ---
    if current_time - last_stat_update > 1.0 then
        last_cpu = math.floor(wm.get_cpu_usage())
        last_ram = math.floor(wm.get_ram_usage())
        last_stat_update = current_time
    end

    local time_str = os.date("%H:%M:%S")
    local stats_x = bar_x + bar_w - 210
    
    -- CPU
    ui.draw_text("\u{E9D9}", stats_x, text_y + 1, 10, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.icon_font_family)
    ui.draw_text(last_cpu .. "%", stats_x + 16, text_y, 11, t.text_color[1], t.text_color[2], t.text_color[3], 1, t.font_family)

    -- RAM
    ui.draw_text("\u{E9A1}", stats_x + 60, text_y + 1, 10, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.icon_font_family)
    ui.draw_text(last_ram .. "%", stats_x + 76, text_y, 11, t.text_color[1], t.text_color[2], t.text_color[3], 1, t.font_family)

    -- Time
    ui.draw_text(time_str, stats_x + 125, text_y, 11, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.font_family)

    -- --- 7. TRAY & CONTROL CENTER TRIGGER ---
    local trigger_x = bar_x + bar_w - 25
    if HyprWin.cc_active then
        ui.fill_rounded_rect(trigger_x - 5, by + 4, 22, 22, 6, t.accent_color[1], t.accent_color[2], t.accent_color[3], 0.3)
    end
    -- Control Center Icon (Gear/Settings)
    ui.draw_text("\u{E713}", trigger_x, text_y + 1, 12, 1, 1, 1, 1, t.icon_font_family)

    -- --- 8. SUB-MODULES RENDER ---
    cc.draw(dt)
end

return topbar