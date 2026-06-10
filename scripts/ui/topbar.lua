-- --- FIXED CODE LOCATOR: scripts/ui/topbar.lua ---
local topbar = {}

local function get_workspace_window_count(ws_id)
    local count = 0
    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd]
        if ws == ws_id then
            count = count + 1
        end
    end
    return count
end

-- Render the top workspace bar with real-time text and clocks
function topbar.draw()
    local sw, _ = wm.get_screen_size()
    
    -- Sleek dark semi-transparent glass bar
    ui.fill_rect(0, 0, sw, 35, 0.015, 0.015, 0.018, 0.88)
    ui.fill_rect(0, 35, sw, 1, 0.7, 0.4, 1.0, 0.25) -- Thin glowing separator

    -- Render Workspace Indicators (Pill/Dots)
    local start_x = 15
    local ind_y = 10
    local ind_w = 20
    local ind_h = 15
    local gap_x = 8

    for i = 1, 9 do
        local x = start_x + (i - 1) * (ind_w + gap_x)
        local count = get_workspace_window_count(i)
        
        if i == HyprWin.current_workspace then
            -- Bright neon pill for the active workspace
            ui.fill_rect(x, ind_y, ind_w, ind_h, 0.7, 0.4, 1.0, 1.0)
            ui.draw_rect(x, ind_y, ind_w, ind_h, 0.8, 0.6, 1.0, 0.8, 1.0)
        elseif count > 0 then
            -- Elegant white-purple dot for workspaces with active windows
            ui.fill_rect(x + 4, ind_y + 4, ind_w - 8, ind_h - 8, 0.45, 0.4, 0.6, 0.85)
            ui.draw_rect(x + 4, ind_y + 4, ind_w - 8, ind_h - 8, 0.7, 0.4, 1.0, 0.4, 1.0)
        else
            -- Dim minimal dot for empty workspaces
            ui.fill_rect(x + 7, ind_y + 5, ind_w - 14, ind_h - 10, 0.12, 0.12, 0.15, 0.5)
        end
    end

    -- Render System Time (Centered)
    local time_str = os.date("%I:%M:%S %p")
    local text_w = #time_str * 8.2 -- Average width approximation for Segoe UI 14pt
    local center_x = (sw - text_w) / 2
    ui.draw_text(time_str, center_x, 9, 14, 0.9, 0.9, 0.95, 0.95, "Segoe UI")

    -- Render Active Window Title (Right Aligned)
    local focused = HyprWin.focused_window
    if focused then
        local title = wm.get_window_title(focused)
        if title and title ~= "" then
            -- Truncate title if it's too long to prevent visual overlap
            if #title > 45 then
                title = string.sub(title, 1, 42) .. "..."
            end
            local title_w = #title * 7.5
            local right_x = sw - title_w - 20
            ui.draw_text(title, right_x, 10, 13, 0.7, 0.7, 0.75, 0.8, "Segoe UI")
        end
    end
end

return topbar