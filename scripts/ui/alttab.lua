-- scripts/ui/alttab.lua
local alttab = {}

HyprWin.alttab_active = HyprWin.alttab_active or false
HyprWin.alttab_index = HyprWin.alttab_index or 1
HyprWin.alttab_windows = HyprWin.alttab_windows or {}

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

function alttab.action(action_type)
    if action_type == "next" then
        if not HyprWin.alttab_active then
            HyprWin.alttab_active = true
            HyprWin.alttab_windows = {}
            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if ws == HyprWin.current_workspace then
                    table.insert(HyprWin.alttab_windows, hwnd)
                end
            end
            HyprWin.alttab_index = (#HyprWin.alttab_windows >= 2) and 2 or 1
        else
            local count = #HyprWin.alttab_windows
            if count > 0 then
                HyprWin.alttab_index = HyprWin.alttab_index + 1
                if HyprWin.alttab_index > count then HyprWin.alttab_index = 1 end
            end
        end
    elseif action_type == "prev" then
        if HyprWin.alttab_active then
            local count = #HyprWin.alttab_windows
            if count > 0 then
                HyprWin.alttab_index = HyprWin.alttab_index - 1
                if HyprWin.alttab_index < 1 then HyprWin.alttab_index = count end
            end
        end
    elseif action_type == "commit" then
        if HyprWin.alttab_active then
            local target = HyprWin.alttab_windows[HyprWin.alttab_index]
            if target and is_valid(target) then wm.focus_window(target) end
            HyprWin.alttab_active = false
            HyprWin.alttab_windows = {}
        end
    end
end

function alttab.draw()
    if not HyprWin.alttab_active then return end

    local count = #HyprWin.alttab_windows
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme

    local item_w, item_h, gap_x, padding = 110, 100, 12, 20
    local modal_w = (count * item_w) + ((count - 1) * gap_x) + (padding * 2)
    local modal_h = item_h + (padding * 2)

    if modal_w < 300 then modal_w = 300 end
    local modal_x = (sw - modal_w) / 2
    local modal_y = (sh - modal_h) / 2

    -- Modal card background and active border
    ui.fill_rounded_rect(modal_x, modal_y, modal_w, modal_h, t.rounding + 4, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4])
    ui.draw_rounded_rect(modal_x, modal_y, modal_w, modal_h, t.rounding + 4, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], t.active_border_color[4], t.border_size)

    local start_x = modal_x + (modal_w - ((count * item_w) + ((count - 1) * gap_x))) / 2

    for i = 1, count do
        local hwnd = HyprWin.alttab_windows[i]
        local item_x = start_x + (i - 1) * (item_w + gap_x)
        local item_y = modal_y + padding
        local is_selected = (i == HyprWin.alttab_index)

        -- Window item styling
        if is_selected then
            ui.fill_rounded_rect(item_x, item_y, item_w, item_h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], 0.95)
            ui.draw_rounded_rect(item_x, item_y, item_w, item_h, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 1.0, 1.5)
        else
            ui.fill_rounded_rect(item_x, item_y, item_w, item_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], 0.5)
            ui.draw_rounded_rect(item_x, item_y, item_w, item_h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], 0.6, 1.0)
        end

        local inner_w, inner_h = 90, 50
        local inner_x = item_x + (item_w - inner_w) / 2
        local inner_y = item_y + 12

        ui.draw_rounded_rect(inner_x, inner_y, inner_w, inner_h, t.rounding - 2, t.border_color[1], t.border_color[2], t.border_color[3], 0.5, 1.0)

        local wx, wy, ww, wh = wm.get_window_rect(hwnd)
        if wm.is_minimized(hwnd) then
            local saved = HyprWin.floating_rects[hwnd]
            if saved then
                wx, wy, ww, wh = saved[1], saved[2], saved[3], saved[4]
            else
                wx, wy, ww, wh = sw / 4, sh / 4, sw / 2, sh / 2
            end
        end

        local scale_x, scale_y = inner_w / sw, inner_h / sh
        local sx = inner_x + (wx * scale_x)
        local sy = inner_y + (wy * scale_y)
        local sww, shh = ww * scale_x, wh * scale_y

        if sx < inner_x then sx = inner_x end
        if sy < inner_y then sy = inner_y end
        if sx + sww > inner_x + inner_w then sww = (inner_x + inner_w) - sx end
        if sy + shh > inner_y + inner_h then shh = (inner_y + inner_h) - sy end

        if is_selected then
            ui.fill_rounded_rect(sx, sy, sww, shh, t.rounding - 4, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.5)
            ui.draw_rounded_rect(sx, sy, sww, shh, t.rounding - 4, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.9, 1.0)
        else
            ui.fill_rounded_rect(sx, sy, sww, shh, t.rounding - 4, t.border_color[1], t.border_color[2], t.border_color[3], 0.3)
            ui.draw_rounded_rect(sx, sy, sww, shh, t.rounding - 4, t.border_color[1], t.border_color[2], t.border_color[3], 0.6, 1.0)
        end

        local raw_title = wm.get_window_title(hwnd)
        local max_chars = 14
        local label = (string.len(raw_title) > max_chars) and (string.sub(raw_title, 1, max_chars) .. "…") or raw_title
        local lx = item_x + (item_w - ui.measure_text(label, 10, t.font_family)) / 2
        local ly = item_y + item_h - 16

        if is_selected then
            ui.draw_text(label, lx, ly, 10, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 1.0, t.font_family)
        else
            ui.draw_text(label, lx, ly, 10, t.text_dim[1], t.text_dim[2], t.text_dim[3], t.text_dim[4], t.font_family)
        end
    end
end

return alttab