-- scripts/ui/topbar.lua
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

-- Render the top workspace bar
function topbar.draw()
    local sw, _ = wm.get_screen_size()
    
    -- Sleek dark semi-transparent glass bar
    ui.fill_rect(0, 0, sw, 35, 0.015, 0.015, 0.018, 0.88)
    ui.fill_rect(0, 35, sw, 1, 0.7, 0.4, 1.0, 0.25) -- Thin glowing separator

    -- Render Workspace Indicators
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
end

return topbar