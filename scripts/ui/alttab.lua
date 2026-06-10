-- scripts/ui/alttab.lua
local alttab = {}

HyprWin.alttab_active = HyprWin.alttab_active or false
HyprWin.alttab_index = HyprWin.alttab_index or 1
HyprWin.alttab_windows = HyprWin.alttab_windows or {}

-- Helper to check if window still exists (allows minimized now)
local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

-- Process keyboard inputs from C++ hook
function alttab.action(action_type)
    if action_type == "next" then
        if not HyprWin.alttab_active then
            -- Open Alt+Tab and build stable list of active workspace windows
            HyprWin.alttab_active = true
            HyprWin.alttab_windows = {}
            
            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if ws == HyprWin.current_workspace then
                    table.insert(HyprWin.alttab_windows, hwnd)
                end
            end

            -- Start selection at index 2 (previous active) if possible
            if #HyprWin.alttab_windows >= 2 then
                HyprWin.alttab_index = 2
            else
                HyprWin.alttab_index = 1
            end
        else
            -- Cycle to next window
            local count = #HyprWin.alttab_windows
            if count > 0 then
                HyprWin.alttab_index = HyprWin.alttab_index + 1
                if HyprWin.alttab_index > count then
                    HyprWin.alttab_index = 1
                end
            end
        end
    elseif action_type == "prev" then
        if HyprWin.alttab_active then
            local count = #HyprWin.alttab_windows
            if count > 0 then
                HyprWin.alttab_index = HyprWin.alttab_index - 1
                if HyprWin.alttab_index < 1 then
                    HyprWin.alttab_index = count
                end
            end
        end
    elseif action_type == "commit" then
        if HyprWin.alttab_active then
            local target = HyprWin.alttab_windows[HyprWin.alttab_index]
            if target and is_valid(target) then
                wm.focus_window(target)
            end
            HyprWin.alttab_active = false
            HyprWin.alttab_windows = {}
        end
    end
end

-- Render the beautiful glassmorphic wireframe layout
function alttab.draw()
    if not HyprWin.alttab_active then return end

    local count = #HyprWin.alttab_windows
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()

    -- Define beautiful modal layout dimensions
    local item_w = 110
    local item_h = 100
    local gap_x = 12
    local padding = 20

    local modal_w = (count * item_w) + ((count - 1) * gap_x) + (padding * 2)
    local modal_h = item_h + (padding * 2)

    -- Clamp modal dimensions to reasonable sizes
    if modal_w < 300 then modal_w = 300 end

    local modal_x = (sw - modal_w) / 2
    local modal_y = (sh - modal_h) / 2

    -- Draw glass-morphic backdrop blur card with purple outline
    ui.fill_rect(modal_x, modal_y, modal_w, modal_h, 0.03, 0.03, 0.05, 0.92)
    ui.draw_rect(modal_x, modal_y, modal_w, modal_h, 0.7, 0.4, 1.0, 1.0, 2.0)

    -- Draw each window node representation in the list
    local start_x = modal_x + (modal_w - ((count * item_w) + ((count - 1) * gap_x))) / 2

    for i = 1, count do
        local hwnd = HyprWin.alttab_windows[i]
        local item_x = start_x + (i - 1) * (item_w + gap_x)
        local item_y = modal_y + padding

        local is_selected = (i == HyprWin.alttab_index)

        -- Base item card styling
        if is_selected then
            ui.fill_rect(item_x, item_y, item_w, item_h, 0.15, 0.12, 0.25, 0.95)
            ui.draw_rect(item_x, item_y, item_w, item_h, 0.7, 0.4, 1.0, 1.0, 1.5)
        else
            ui.fill_rect(item_x, item_y, item_w, item_h, 0.06, 0.06, 0.08, 0.8)
            ui.draw_rect(item_x, item_y, item_w, item_h, 0.15, 0.15, 0.18, 0.6, 1.0)
        end

        -- Inner schematics bounds representing target screen aspect ratio (scaled)
        local inner_w = 90
        local inner_h = 50
        local inner_x = item_x + (item_w - inner_w) / 2
        local inner_y = item_y + 12

        -- Mini mock-monitor screen outline
        ui.draw_rect(inner_x, inner_y, inner_w, inner_h, 0.25, 0.25, 0.3, 0.5, 1.0)

        -- Draw relative miniature wireframe window layout on target screen
        local wx, wy, ww, wh = wm.get_window_rect(hwnd)
        
        -- If window is minimized, use its last known floating coordinates, or render a centered placeholder
        if wm.is_minimized(hwnd) then
            local saved = HyprWin.floating_rects[hwnd]
            if saved then
                wx, wy, ww, wh = saved[1], saved[2], saved[3], saved[4]
            else
                wx, wy, ww, wh = sw / 4, sh / 4, sw / 2, sh / 2
            end
        end

        local scale_x = inner_w / sw
        local scale_y = inner_h / sh

        local sx = inner_x + (wx * scale_x)
        local sy = inner_y + (wy * scale_y)
        local sww = ww * scale_x
        local shh = wh * scale_y

        -- Ensure we do not bleed out of mock-monitor margins
        if sx < inner_x then sx = inner_x end
        if sy < inner_y then sy = inner_y end
        if sx + sww > inner_x + inner_w then sww = (inner_x + inner_w) - sx end
        if sy + shh > inner_y + inner_h then shh = (inner_y + inner_h) - sy end

        -- Display scaled wireframe node inside mock monitor
        if is_selected then
            ui.fill_rect(sx, sy, sww, shh, 0.7, 0.4, 1.0, 0.5)
            ui.draw_rect(sx, sy, sww, shh, 0.7, 0.4, 1.0, 0.9, 1.0)
        else
            ui.fill_rect(sx, sy, sww, shh, 0.25, 0.25, 0.3, 0.3)
            ui.draw_rect(sx, sy, sww, shh, 0.4, 0.4, 0.45, 0.6, 1.0)
        end
    end
end

return alttab