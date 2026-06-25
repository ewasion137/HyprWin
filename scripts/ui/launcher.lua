-- scripts/ui/launcher.lua
local launcher = {}

HyprWin.launcher_active = false
HyprWin.launcher_index  = 1

local ITEM_H      = 38
local ITEM_MARGIN = 6
local PADDING     = 20

local apps = {
    { name = "Brave Browser",         path = "brave.exe"                         },
    { name = "Visual Studio Code",    path = "code"                              },
    { name = "Discord",               path = "discord"                           },
    { name = "FL Studio 2025",        path = "FL64.exe"                          },
    { name = "Task Manager",          path = "taskmgr.exe"                       },
    { name = "Command Prompt",        path = "cmd.exe"                           },
    { name = "File Explorer",         path = "explorer.exe"                      },
    { name = "Lock Workstation",      path = "rundll32.exe user32.dll,LockWorkStation", is_system = true, icon = "\u{E72E}" },
    { name = "Restart Computer",      path = "shutdown.exe /r /t 0",                    is_system = true, icon = "\u{E777}" },
    { name = "Shut Down Computer",    path = "shutdown.exe /s /t 0",                    is_system = true, icon = "\u{E7E8}" },
}

function launcher.toggle()
    HyprWin.launcher_active = not HyprWin.launcher_active
    HyprWin.launcher_index  = 1
end

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

function launcher.commit()
    if not HyprWin.launcher_active then return end
    local app = apps[HyprWin.launcher_index]
    if app then wm.spawn(app.path) end
    HyprWin.launcher_active = false
end

function launcher.draw(alpha)
    if alpha < 0.01 then return end

    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme

    local panel_w = 480
    local panel_h = PADDING * 2 + 54 + (#apps * (ITEM_H + ITEM_MARGIN)) + 10
    local panel_x = (sw - panel_w) / 2
    local panel_y = (sh - panel_h) / 2 - (18 * (1 - alpha))

    -- Design Tokens Alignment
    ui.fill_rounded_rect(panel_x, panel_y, panel_w, panel_h, t.rounding + 6, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4] * alpha)
    ui.draw_rounded_rect(panel_x, panel_y, panel_w, panel_h, t.rounding + 6, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], t.active_border_color[4] * 0.50 * alpha, t.border_size)

    local sb_x = panel_x + PADDING
    local sb_y = panel_y + PADDING
    local sb_w = panel_w - PADDING * 2
    ui.fill_rounded_rect(sb_x, sb_y, sb_w, 36, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], 0.20 * alpha)
    ui.draw_rounded_rect(sb_x, sb_y, sb_w, 36, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], t.active_border_color[4] * 0.30 * alpha, 1)
    ui.draw_text("  Launch Application", sb_x + 10, sb_y + 10, 14, t.text_color[1], t.text_color[2], t.text_color[3], t.text_color[4] * alpha, t.font_family)

    local list_start_y = sb_y + 36 + ITEM_MARGIN + 6

    for i, app in ipairs(apps) do
        local ix = sb_x
        local iy = list_start_y + (i - 1) * (ITEM_H + ITEM_MARGIN)

        if app.is_system and not apps[i-1].is_system then
            local sep_y = iy - (ITEM_MARGIN / 2) - 3
            ui.fill_rect(ix, sep_y, sb_w, 1, t.border_color[1], t.border_color[2], t.border_color[3], 0.40 * alpha)
        end

        local is_sel = (i == HyprWin.launcher_index)

        if is_sel then
            if app.is_system then
                local hz = t.accent_danger
                ui.fill_rounded_rect(ix, iy, sb_w, ITEM_H, t.rounding - 2, hz[1], hz[2], hz[3], 0.35 * alpha)
                ui.draw_rounded_rect(ix, iy, sb_w, ITEM_H, t.rounding - 2, hz[1], hz[2], hz[3], hz[4] * alpha, 1.2)
                ui.draw_text(app.icon, ix + 14, iy + (ITEM_H - 12) / 2 + 1, 12, hz[1], hz[2], hz[3], alpha, t.icon_font_family)
                ui.draw_text(app.name, ix + 36, iy + (ITEM_H - 14) / 2, 14, t.text_color[1], t.text_color[2], t.text_color[3], alpha, t.font_family)
            else
                local hz = t.accent_teal
                ui.fill_rounded_rect(ix, iy, sb_w, ITEM_H, t.rounding - 2, hz[1], hz[2], hz[3], 0.35 * alpha)
                ui.draw_rounded_rect(ix, iy, sb_w, ITEM_H, t.rounding - 2, hz[1], hz[2], hz[3], hz[4] * alpha, 1.2)
                ui.draw_text(app.name, ix + 14, iy + (ITEM_H - 14) / 2, 14, t.text_color[1], t.text_color[2], t.text_color[3], alpha, t.font_family)
            end
        else
            ui.fill_rounded_rect(ix, iy, sb_w, ITEM_H, t.rounding - 2, t.bg_color[1], t.bg_color[2], t.bg_color[3], 0.60 * alpha)
            if app.is_system then
                local hz = t.accent_danger
                ui.draw_text(app.icon, ix + 14, iy + (ITEM_H - 12) / 2 + 1, 12, hz[1], hz[2], hz[3], 0.80 * alpha, t.icon_font_family)
                ui.draw_text(app.name, ix + 36, iy + (ITEM_H - 14) / 2, 13, t.text_dim[1], t.text_dim[2], t.text_dim[3], t.text_dim[4] * alpha, t.font_family)
            else
                ui.draw_text(app.name, ix + 14, iy + (ITEM_H - 14) / 2, 13, t.text_dim[1], t.text_dim[2], t.text_dim[3], t.text_dim[4] * alpha, t.font_family)
            end
        end
    end
end

return launcher