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
function launcher.draw()
    if not HyprWin.launcher_active then return end

    local sw, sh = wm.get_screen_size()
    local w = 450
    local h = (#apps * 35) + 40
    local x = (sw - w) / 2
    local y = (sh - h) / 2

    -- Draw glass backdrop card with bright green/cyan cyberpunk outline
    ui.fill_rect(x, y, w, h, 0.02, 0.02, 0.03, 0.94)
    ui.draw_rect(x, y, w, h, 0.2, 0.8, 0.7, 1.0, 2.0)

    -- Draw Title Header
    ui.draw_text("SYSTEM APPLICATION LAUNCHER", x + 20, y + 15, 12, 0.2, 0.8, 0.7, 0.8, "Segoe UI")
    ui.fill_rect(x + 20, y + 35, w - 40, 1, 0.2, 0.8, 0.7, 0.3)

    -- Draw list of apps
    for i, app in ipairs(apps) do
        local item_y = y + 45 + (i - 1) * 35
        local is_selected = (i == HyprWin.launcher_index)

        if is_selected then
            -- Highlight active app
            ui.fill_rect(x + 15, item_y, w - 30, 28, 0.1, 0.25, 0.22, 0.9)
            ui.draw_rect(x + 15, item_y, w - 30, 28, 0.2, 0.8, 0.7, 0.9, 1.0)
            ui.draw_text("> " .. app.name, x + 25, item_y + 6, 13, 0.2, 0.9, 0.8, 1.0, "Segoe UI")
        else
            -- Dim inactive app
            ui.draw_text("  " .. app.name, x + 25, item_y + 6, 13, 0.7, 0.7, 0.75, 0.7, "Segoe UI")
        end
    end
end

return launcher