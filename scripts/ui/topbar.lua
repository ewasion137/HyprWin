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
function topbar.draw(anim_y)
    local sw, _ = wm.get_screen_size()
    
    -- Floating bar style
    local bar_w = sw - 40
    local bar_x = 20
    
    -- Main bar background (Rounded)
    ui.fill_rounded_rect(bar_x, anim_y + 5, bar_w, 30, 10, 0.02, 0.02, 0.03, 0.9)
    ui.draw_rounded_rect(bar_x, anim_y + 5, bar_w, 30, 10, 0.7, 0.4, 1.0, 0.3, 1.5)

    -- Workspace indicators with "Active" sliding logic would go here
    -- (Simplified for clarity)
    for i = 1, 9 do
        local color = (i == HyprWin.current_workspace) and {0.7, 0.4, 1.0, 1} or {0.2, 0.2, 0.25, 0.8}
        ui.fill_rounded_rect(bar_x + 15 + (i-1)*25, anim_y + 12, 18, 16, 4, color[1], color[2], color[3], color[4])
    end
end

return topbar