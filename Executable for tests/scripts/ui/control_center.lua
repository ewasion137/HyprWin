local cc = {}

HyprWin.cc_active = false
local anim_val = 0

function cc.toggle()
    HyprWin.cc_active = not HyprWin.cc_active
end

function cc.draw(dt)
    local target = HyprWin.cc_active and 1 or 0
    anim_val = anim_val + (target - anim_val) * 0.2
    if anim_val < 0.01 then return end

    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme
    local w, h = 300, 360
    local x = sw - w - 16
    local y = t.bar_height + 15

    ui.fill_rounded_rect(x, y, w, h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4] * anim_val)
    ui.draw_rounded_rect(x, y, w, h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], 0.4 * anim_val, 1)
end

return cc