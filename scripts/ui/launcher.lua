-- scripts/ui/launcher.lua
local launcher = {}

HyprWin.launcher_active = false
HyprWin.launcher_index = 1

-- List of favorite apps to launch (Add or modify paths freely)
local apps = {
    { name = "Brave Browser", path = "brave.exe" },
    { name = "Visual Studio Code", path = "code" },
    { name = "Discord", path = "discord" },
    { name = "FL Studio 2025", path = "FL64.exe" },
    { name = "Task Manager", path = "taskmgr.exe" },
    { name = "Command Prompt", path = "cmd.exe" },
    { name = "Explorer File Manager", path = "explorer.exe /separate,C:\\" }
}

function launcher.toggle()
    HyprWin.launcher_active = not HyprWin.launcher_active
    HyprWin.launcher_index = 1
end

-- Navigate inside the launcher utilizing your standard Vim hotkeys
function launcher.navigate(dir)
    if not HyprWin.launcher_active then return end
    if dir == "down" then
        HyprWin.launcher_index = HyprWin.launcher_index + 1
        if HyprWin.launcher_index > #apps then HyprWin.launcher_index = 1 end
    elseif dir == "up" then
        HyprWin.launcher_index = HyprWin.launcher_index - 1
        if HyprWin.launcher_index < 1 then HyprWin.launcher_index = #apps end
    end
end

-- Execute the selected application and close menu
function launcher.commit()
    if not HyprWin.launcher_active then return end
    local app = apps[HyprWin.launcher_index]
    if app then
        wm.spawn(app.path)
    end
    HyprWin.launcher_active = false
end

-- Draw the beautiful launcher overlay card
function launcher.draw(alpha)
    if alpha < 0.01 then return end

    local sw, sh = wm.get_screen_size()
    local w, h = 500, 400
    local x, y = (sw - w) / 2, (sh - h) / 2 - (20 * (1 - alpha)) -- Slight slide-up

    -- Glassmorphism effect
    ui.fill_rounded_rect(x, y, w, h, 15, 0.01, 0.01, 0.02, 0.95 * alpha)
    ui.draw_rounded_rect(x, y, w, h, 15, 0.2, 0.8, 0.7, 0.8 * alpha, 2)

    -- Search bar visual
    ui.fill_rounded_rect(x + 20, y + 20, w - 40, 40, 8, 0.05, 0.05, 0.08, 1 * alpha)
    ui.draw_text("Search apps...", x + 35, y + 30, 14, 0.5, 0.5, 0.5, 0.6 * alpha, "Segoe UI Variable")
    
    -- Active selection highlight
    local item_y = y + 80 + (HyprWin.launcher_index - 1) * 40
    ui.fill_rounded_rect(x + 20, item_y, w - 40, 35, 6, 0.2, 0.8, 0.7, 0.2 * alpha)
end

return launcher