-- scripts/ui/topbar.lua
local topbar = {}

local BAR_MARGIN  = 5
local WS_BOX_W    = 18
local WS_BOX_H    = 16
local WS_SPACING  = 25
local WS_OFFSET_X = 15

local function ws_window_count(ws_id)
    local count = 0
    for _, hwnd in ipairs(HyprWin.windows) do
        if HyprWin.window_workspaces[hwnd] == ws_id then count = count + 1 end
    end
    return count
end

local function get_time_string()
    return os.date("%H:%M")
end

function topbar.draw(anim_y)
    local sw, _ = wm.get_screen_size()
    local t = HyprWin.theme
    local by = anim_y + BAR_MARGIN

    local bar_w = sw - 40
    local bar_x = 20

    -- Outer Bar layout
    ui.fill_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4])
    ui.draw_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.30, 1.5)

    -- Dynamic Workspaces
    for i = 1, 9 do
        local is_active = (i == HyprWin.current_workspace)
        local has_wins  = (ws_window_count(i) > 0)

        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        local wy = by + (t.bar_height - WS_BOX_H) / 2

        if is_active then
            local hz = t.accent_color
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, t.rounding - 4, hz[1], hz[2], hz[3], hz[4])
            ui.draw_text(tostring(i), wx + 5, wy + 1, 11, 1, 1, 1, 1, t.font_family)
        elseif has_wins then
            local hz = t.accent_color
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, t.rounding - 4, hz[1], hz[2], hz[3], 0.25)
            ui.draw_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, t.rounding - 4, hz[1], hz[2], hz[3], 0.40, 1.0)
            ui.draw_text("\u{E7F4}", wx + 3, wy + 2, 9, hz[1], hz[2], hz[3], 0.85, t.icon_font_family)
        else
            ui.fill_rounded_rect(wx, wy, WS_BOX_W, WS_BOX_H, t.rounding - 4, t.border_color[1], t.border_color[2], t.border_color[3], 0.70)
        end
    end

    -- System Stats Block
    local cpu      = math.floor(wm.get_cpu_usage())
    local ram      = math.floor(wm.get_ram_usage())
    local time_str = get_time_string()
    local ram_str  = string.format("%d%%", ram)
    local cpu_str  = string.format("%d%%", cpu)

    local text_y   = by + (t.bar_height - 12) / 2 - 1
    local icon_w   = 14
    local spacing  = 16
    local cur_x    = bar_x + bar_w - 20

    -- Clock
    local time_w = ui.measure_text(time_str, 12, t.font_family)
    cur_x = cur_x - time_w
    ui.draw_text(time_str, cur_x, text_y, 12, t.text_color[1], t.text_color[2], t.text_color[3], t.text_color[4], t.font_family)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E121}", cur_x, text_y + 1, 11, t.accent_color[1], t.accent_color[2], t.accent_color[3], t.accent_color[4], t.icon_font_family)

    -- Memory
    local ram_w = ui.measure_text(ram_str, 12, t.font_family)
    cur_x = cur_x - spacing - ram_w
    ui.draw_text(ram_str, cur_x, text_y, 12, t.text_color[1], t.text_color[2], t.text_color[3], t.text_color[4], t.font_family)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E9A1}", cur_x, text_y + 1, 11, t.accent_color[1], t.accent_color[2], t.accent_color[3], t.accent_color[4], t.icon_font_family)

    -- CPU
    local cpu_w = ui.measure_text(cpu_str, 12, t.font_family)
    cur_x = cur_x - spacing - cpu_w
    ui.draw_text(cpu_str, cur_x, text_y, 12, t.text_color[1], t.text_color[2], t.text_color[3], t.text_color[4], t.font_family)
    cur_x = cur_x - icon_w - 4
    ui.draw_text("\u{E9D9}", cur_x, text_y + 1, 11, t.accent_color[1], t.accent_color[2], t.accent_color[3], t.accent_color[4], t.icon_font_family)

    -- Centered Title
    if HyprWin.focused_window then
        local title   = wm.get_window_title(HyprWin.focused_window)
        local title_w = ui.measure_text(title, 12, t.font_family)
        local title_x = bar_x + (bar_w - title_w) / 2
        ui.draw_text(title, title_x, text_y, 12, t.text_color[1], t.text_color[2], t.text_color[3], 0.80, t.font_family)
    end
end

return topbar