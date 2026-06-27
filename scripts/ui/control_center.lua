local cc = {}
HyprWin.cc_active = false
local anim_val = 0

function cc.toggle()
    HyprWin.cc_active = not HyprWin.cc_active
end

function cc.draw(dt)
    -- Плавное появление (lerp)
    local target = HyprWin.cc_active and 1 or 0
    anim_val = anim_val + (target - anim_val) * 0.15
    if anim_val < 0.01 then return end

    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme
    
    local w, h = 320, 400
    local x = sw - w - 16
    local y = t.bar_height + 15 - (20 * (1 - anim_val)) -- Выплывает снизу вверх

    -- Фон меню
    ui.fill_rounded_rect(x, y, w, h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4] * anim_val)
    ui.draw_rounded_rect(x, y, w, h, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.3 * anim_val, 1)

    -- Сетка кнопок (Quick Settings)
    local btn_w, btn_h = (w - 60) / 2, 45
    local function draw_btn(label, icon, bx, by, active)
        local bg = active and t.accent_color or {0.2, 0.2, 0.2, 0.5}
        
        -- Default text is white
        local text_r, text_g, text_b = 1.0, 1.0, 1.0
        
        -- Smart brightness calculation (0.299R + 0.587G + 0.114B)
        if active then
            local brightness = (bg[1] * 0.299) + (bg[2] * 0.587) + (bg[3] * 0.114)
            if brightness > 0.6 then
                text_r, text_g, text_b = 0.05, 0.05, 0.05 -- Use dark text for light backgrounds
            end
        end

        ui.fill_rounded_rect(bx, by, btn_w, btn_h, 8, bg[1], bg[2], bg[3], bg[4] * anim_val)
        ui.draw_text(icon, bx + 12, by + 14, 12, text_r, text_g, text_b, anim_val, t.icon_font_family)
        ui.draw_text(label, bx + 35, by + 15, 11, text_r, text_g, text_b, anim_val, t.font_family)
    end

    draw_btn("Wi-Fi", "\u{E701}", x + 20, y + 20, true)
    draw_btn("Bluetooth", "\u{E702}", x + 30 + btn_w, y + 20, false)
    draw_btn("Night Light", "\u{E975}", x + 20, y + 75, true)
    draw_btn("Focus", "\u{E10F}", x + 30 + btn_w, y + 75, false)

    -- Слайдеры (Громкость / Яркость)
    local function draw_slider(label, icon, sy)
        ui.draw_text(label, x + 20, sy, 10, t.text_dim[1], t.text_dim[2], t.text_dim[3], anim_val, t.font_family)
        ui.fill_rounded_rect(x + 20, sy + 15, w - 40, 6, 3, 0.1, 0.1, 0.1, 0.8 * anim_val)
        ui.fill_rounded_rect(x + 20, sy + 15, (w - 40) * 0.7, 6, 3, t.accent_color[1], t.accent_color[2], t.accent_color[3], 1.0 * anim_val)
        ui.fill_rounded_rect(x + 20 + (w-40)*0.7 - 5, sy + 13, 10, 10, 5, 1, 1, 1, anim_val)
    end

    draw_slider("Volume", "\u{E767}", y + 150)
    draw_slider("Brightness", "\u{E706}", y + 210)

    -- Power Buttons
    local px = x + 20
    local py = y + h - 50
    ui.draw_text("\u{E7E8} Power Off", px, py, 11, 0.9, 0.3, 0.3, anim_val, t.font_family)
    ui.draw_text("\u{E777} Reboot", px + 120, py, 11, 1, 1, 1, anim_val, t.font_family)
end

return cc