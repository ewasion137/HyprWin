local launcher = {}

HyprWin.launcher_active = false
HyprWin.launcher_index  = 1

local FONT        = "Segoe UI Variable"
local ITEM_H      = 38
local ITEM_MARGIN = 6
local PADDING     = 20

-- App list — paths are passed directly to ShellExecute (wm.spawn)
local apps = {
    { name = "Brave Browser",         path = "brave.exe"                         },
    { name = "Visual Studio Code",    path = "code"                              },
    { name = "Discord",               path = "discord"                           },
    { name = "FL Studio 2025",        path = "FL64.exe"                          },
    { name = "Task Manager",          path = "taskmgr.exe"                       },
    { name = "Command Prompt",        path = "cmd.exe"                           },
    { name = "File Explorer",         path = "explorer.exe"                      },
}

function launcher.toggle()
    HyprWin.launcher_active = not HyprWin.launcher_active
    HyprWin.launcher_index  = 1
end

-- Navigate the list with Vim-style keys (J/K)
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

-- Execute selected app and close the launcher
function launcher.commit()
    if not HyprWin.launcher_active then return end
    local app = apps[HyprWin.launcher_index]
    if app then
        wm.spawn(app.path)
    end
    HyprWin.launcher_active = false
end

function launcher.draw(alpha)
    if alpha < 0.01 then return end

    local sw, sh = wm.get_screen_size()

    local panel_w = 480
    local panel_h = PADDING * 2 + 50 + (#apps * (ITEM_H + ITEM_MARGIN))
    local panel_x = (sw - panel_w) / 2
    -- Slide-up entrance animation driven by alpha
    local panel_y = (sh - panel_h) / 2 - (18 * (1 - alpha))

    -- Glassmorphism card background
    ui.fill_rounded_rect(panel_x, panel_y, panel_w, panel_h, 14, 0.01, 0.01, 0.02, 0.95 * alpha)
    ui.draw_rounded_rect(panel_x, panel_y, panel_w, panel_h, 14, 0.20, 0.80, 0.70, 0.80 * alpha, 1.8)

    -- Search bar header (static label — real search input requires IME work outside scope)
    local sb_x = panel_x + PADDING
    local sb_y = panel_y + PADDING
    local sb_w = panel_w - PADDING * 2
    ui.fill_rounded_rect(sb_x, sb_y, sb_w, 36, 8, 0.05, 0.05, 0.08, alpha)
    ui.draw_rounded_rect(sb_x, sb_y, sb_w, 36, 8, 0.20, 0.80, 0.70, 0.40 * alpha, 1)
    ui.draw_text("  Launch", sb_x + 10, sb_y + 10, 14, 0.55, 0.55, 0.60, 0.70 * alpha, FONT)

    -- App entry list
    local list_start_y = sb_y + 36 + ITEM_MARGIN + 4

    for i, app in ipairs(apps) do
        local ix = sb_x
        local iy = list_start_y + (i - 1) * (ITEM_H + ITEM_MARGIN)

        local is_sel = (i == HyprWin.launcher_index)

        if is_sel then
            -- Selected row: teal-tinted highlight
            ui.fill_rounded_rect(ix, iy, sb_w, ITEM_H, 7, 0.10, 0.50, 0.45, 0.35 * alpha)
            ui.draw_rounded_rect(ix, iy, sb_w, ITEM_H, 7, 0.20, 0.80, 0.70, 0.70 * alpha, 1.2)
            ui.draw_text(app.name, ix + 14, iy + (ITEM_H - 14) / 2, 14, 0.90, 0.95, 0.95, alpha, FONT)
        else
            ui.fill_rounded_rect(ix, iy, sb_w, ITEM_H, 7, 0.04, 0.04, 0.06, 0.60 * alpha)
            ui.draw_text(app.name, ix + 14, iy + (ITEM_H - 14) / 2, 13, 0.60, 0.62, 0.68, 0.85 * alpha, FONT)
        end
    end
end

return launcher
