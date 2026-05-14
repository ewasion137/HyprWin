-- scripts/main.lua

HyprWin = {}

-- Basic event dispatcher
HyprWin.dispatch_event = function(event_type, hwnd, title)
    -- EVENT_OBJECT_SHOW (Window Created)
    if event_type == 0x8002 then
        log("Tiling new window: " .. title)
        
        -- Get primary monitor resolution
        local sw, sh = wm.get_screen_size()
        
        -- Simple Tile: Put new window on the left half
        wm.move_window(hwnd, 0, 0, sw / 2, sh)
    end
    
    if event_type == 0x8003 then
        log("Window removed from layout: " .. hwnd)
    end
end

log("HyprWin: Tiling engine ready.")