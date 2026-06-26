local topbar = {}

local BAR_MARGIN  = 8
local WS_W        = 24
local WS_H        = 18
local WS_SPACING  = 30
local WS_OFFSET_X = 20

local function ws_window_count(ws_id)
    local count = 0
    for _, hwnd in ipairs(HyprWin.windows) do
        if HyprWin.window_workspaces[hwnd] == ws_id then count = count + 1 end
    end
    return count
end

function topbar.draw(anim_y)
    local sw, _ = wm.get_screen_size()
    local t = HyprWin.theme
    local by = anim_y + BAR_MARGIN

    -- Calculate bar width and center it
    local bar_w = sw - 32
    local bar_x = 16

    -- Main Bar Background (Glassmorphism style)
    ui.fill_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4])
    ui.draw_rounded_rect(bar_x, by, bar_w, t.bar_height, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.2, 1)

    -- --- LEFT SECTION: Workspaces (Pill style) ---
    for i = 1, 7 do -- Reduced to 7 for cleaner look
        local is_active = (i == HyprWin.current_workspace)
        local has_wins  = (ws_window_count(i) > 0)

        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        local wy = by + (t.bar_height - WS_H) / 2

        if is_active then
            -- Active workspace pill
            ui.fill_rounded_rect(wx - 4, wy, WS_W + 8, WS_H, WS_H/2, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1.0)
            ui.draw_text(tostring(i), wx + 6, wy + 2, 11, 0, 0, 0, 1, t.font_family)
        elseif has_wins then
            -- Occupied workspace
            ui.fill_rounded_rect(wx, wy, WS_W, WS_H, WS_H/2, t.text_color[1], t.text_color[2], t.text_color[3], 0.2)
            ui.draw_text(tostring(i), wx + 7, wy + 2, 10, t.text_color[1], t.text_color[2], t.text_color[3], 0.9, t.font_family)
        else
            -- Empty workspace dot
            ui.fill_rounded_rect(wx + 8, wy + 6, 6, 6, 3, t.text_dim[1], t.text_dim[2], t.text_dim[3], 0.4)
        end
    end

    -- --- CENTER SECTION: Active Title ---
    if HyprWin.focused_window then
        local title = wm.get_window_title(HyprWin.focused_window)
        if title:len() > 40 then title = title:sub(1, 37) .. "..." end
        local title_w = ui.measure_text(title, 11, t.font_family)
        ui.draw_text(title, bar_x + (bar_w - title_w) / 2, by + (t.bar_height - 12) / 2, 11, t.text_color[1], t.text_color[2], t.text_color[3], 0.7, t.font_family)
    end

    -- --- RIGHT SECTION: System Stats ---
    local cpu = math.floor(wm.get_cpu_usage())
    local ram = math.floor(wm.get_ram_usage())
    local time_str = os.date("%H:%M:%S")
    
    local stats_x = bar_x + bar_w - 180
    local text_y = by + (t.bar_height - 12) / 2

    -- Replaced NerdFont icons with standard MDL2 or ASCII for safety
    -- CPU (MDL2: \u{E9D9})
    ui.draw_text("\u{E9D9}", stats_x, text_y + 1, 10, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.icon_font_family)
    ui.draw_text(cpu .. "%", stats_x + 16, text_y, 11, t.text_color[1], t.text_color[2], t.text_color[3], 1, t.font_family)

    -- RAM (MDL2: \u{E9A1})
    ui.draw_text("\u{E9A1}", stats_x + 55, text_y + 1, 10, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.icon_font_family)
    ui.draw_text(ram .. "%", stats_x + 71, text_y, 11, t.text_color[1], t.text_color[2], t.text_color[3], 1, t.font_family)

    -- Time
    ui.draw_text(time_str, stats_x + 110, text_y, 11, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1, t.font_family)
end

return topbar