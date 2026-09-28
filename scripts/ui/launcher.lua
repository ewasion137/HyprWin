-- scripts/ui/launcher.lua
local launcher = {}

HyprWin.launcher_active = false
HyprWin.launcher_index  = 1

-- Global app list: define in your hyprland.lua as HyprWin.apps = { ... }
HyprWin.apps = HyprWin.apps or {
    { name = "Terminal",       path = "cmd.exe" },
    { name = "Explorer",       path = "explorer.exe" },
    { name = "Browser",        path = "brave.exe" }
}

function launcher.toggle()
    HyprWin.launcher_active = not HyprWin.launcher_active
    HyprWin.launcher_index  = 1
end

function launcher.navigate(dir)
    if not HyprWin.launcher_active then return end
    local count = #HyprWin.apps
    if dir == "down" then
        HyprWin.launcher_index = (HyprWin.launcher_index % count) + 1
    elseif dir == "up" then
        HyprWin.launcher_index = (HyprWin.launcher_index - 2 + count) % count + 1
    end
end

function launcher.commit()
    if not HyprWin.launcher_active then return end
    local app = HyprWin.apps[HyprWin.launcher_index]
    if app then wm.spawn(app.path) end
    HyprWin.launcher_active = false
end

function launcher.draw(alpha)
    if alpha < 0.01 then return end
    
    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme
    local apps = HyprWin.apps

    local item_h = 40
    local panel_w = 400
    local panel_h = 60 + (#apps * (item_h + 4))
    local px, py = (sw - panel_w) / 2, (sh - panel_h) / 2

    -- Shadow / Blur proxy
    ui.fill_rounded_rect(px + 4, py + 4, panel_w, panel_h, t.rounding, 0, 0, 0, 0.3 * alpha)
    ui.fill_rounded_rect(px, py, panel_w, panel_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4] * alpha)
    ui.draw_rounded_rect(px, py, panel_w, panel_h, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.4 * alpha, 2)

    ui.draw_text("RUN APPLICATION", px + 20, py + 15, 10, t.accent_color[1], t.accent_color[2], t.accent_color[3], alpha, t.font_family)

    for i, app in ipairs(apps) do
        local iy = py + 45 + (i-1) * (item_h + 4)
        local is_sel = (i == HyprWin.launcher_index)
        
        if is_sel then
            ui.fill_rounded_rect(px + 10, iy, panel_w - 20, item_h, 6, t.accent_color[1], t.accent_color[2], t.accent_color[3], 0.2 * alpha)
            ui.draw_text("> " .. app.name, px + 25, iy + 12, 13, 1, 1, 1, alpha, t.font_family)
        else
            ui.draw_text("  " .. app.name, px + 25, iy + 12, 13, t.text_dim[1], t.text_dim[2], t.text_dim[3], alpha, t.font_family)
        end
    end
end

return launcher