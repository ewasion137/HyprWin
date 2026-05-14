-- scripts/main.lua

-- Global table for HyprWin core communication
HyprWin = {}

-- Dispatcher called from C++
HyprWin.dispatch_event = function(event_type, hwnd, title)
    -- EVENT_OBJECT_SHOW = 0x8002
    if event_type == 0x8002 then
        log("Window Opened: [" .. title .. "] HWND: " .. hwnd)
    end
    
    -- EVENT_OBJECT_HIDE = 0x8003
    if event_type == 0x8003 then
        log("Window Closed/Hidden: HWND: " .. hwnd)
    end
end

log("HyprWin Lua logic started from scripts/main.lua")