-- scripts/ui/topbar.lua
local topbar = {}

-- Render the top workspace bar
function topbar.draw()
    local sw, _ = wm.get_screen_size()
    
    -- Simple Top Bar background
    ui.fill_rect(0, 0, sw, 35, 0.02, 0.02, 0.02, 0.9)
    ui.fill_rect(0, 35, sw, 2, 0.7, 0.4, 1.0, 1.0)

    -- Render workspace indicators
    local ind_w = 20
    local ind_h = 14
    local start_x = 15
    local start_y = 10
    local gap_x = 8

    for i = 1, 9 do
        local x = start_x + (i - 1) * (ind_w + gap_x)
        if i == HyprWin.current_workspace then
            -- Active workspace in bright purple
            ui.fill_rect(x, start_y, ind_w, ind_h, 0.7, 0.4, 1.0, 1.0)
        else
            -- Inactive workspaces in dark gray
            ui.fill_rect(x, start_y, ind_w, ind_h, 0.15, 0.15, 0.15, 0.8)
        end
    end
end

return topbar