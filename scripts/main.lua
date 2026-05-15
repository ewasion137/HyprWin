-- scripts/main.lua

HyprWin = {}

-- Dispatcher called from C++
HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    
    -- Ignore known system junk
    if class == "Chrome_ChildWin_Templ" or class:find("Tip") or class:find("Menu") then
        return
    end

    -- EVENT_OBJECT_SHOW (Window Created)
    if event_type == 0x8002 then
        -- Only tile if it's not a ghost window
        if title ~= "" and title ~= "Program Manager" then
            log("Tiling window: [" .. title .. "] | Class: " .. class)
            
            local sw, sh = wm.get_screen_size()
            wm.move_window(hwnd, 50, 50, sw - 100, sh - 100) -- Simple centered tile for test
        end
    end
end

log("HyprWin: Tiling engine ready. Garbage filter improved.")

HyprWin.on_render = function()
    -- Big solid purple square to verify transparency and rendering
    ui.fill_rect(100, 100, 400, 400, 0.5, 0.0, 1.0, 0.8)
    
    -- Small border around it
    ui.draw_rect(100, 100, 400, 400, 1.0, 1.0, 1.0, 1.0, 2.0)
end