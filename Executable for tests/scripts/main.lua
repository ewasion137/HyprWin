HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
HyprWin.current_workspace = 1
HyprWin.window_workspaces = {} 
HyprWin.floating_windows = {}  
HyprWin.floating_rects = {}    
HyprWin.sticky_windows = {}
HyprWin.fullscreen_windows = {}
HyprWin.workspace_ratios = {}
HyprWin.layout_mode = "bsp"
HyprWin.anim_speed = 0.28

-- НОВОЕ: Window groups (табы)
HyprWin.window_groups = {}  -- { group_id = {hwnd1, hwnd2, ...} }
HyprWin.window_to_group = {} -- { hwnd = group_id }
HyprWin.active_in_group = {} -- { group_id = active_hwnd }
HyprWin.next_group_id = 1

-- Geometry caching and animations
HyprWin.window_rects = {}
HyprWin.original_rects = {}
HyprWin.new_windows = {}
HyprWin.window_targets = {}
HyprWin.window_currents = {}

local is_retiling = false

-- --- THEME DESIGN SYSTEM TOKENS ---
HyprWin.theme = {
    gaps_in = 5,
    gaps_out = 15,
    border_size = 2,
    active_opacity = 1.0,
    inactive_opacity = 0.85,
    rounding = 8,
    font_family = "Segoe UI Variable",
    icon_font_family = "Segoe MDL2 Assets",
    
    bg_color = { 0.02, 0.02, 0.03, 0.90 },
    border_color = { 0.15, 0.15, 0.18, 0.60 },
    active_border_color = { 0.70, 0.40, 1.00, 1.00 },
    accent_color = { 0.70, 0.40, 1.00, 1.00 },
    accent_teal = { 0.20, 0.80, 0.70, 1.00 },
    accent_danger = { 0.90, 0.25, 0.35, 1.00 },
    text_color = { 0.85, 0.85, 0.95, 0.90 },
    text_dim = { 0.55, 0.55, 0.60, 0.80 },
    
    bar_height = 30
}

-- Trim helper (Must be defined first for other modules to use it on load)
function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Filter list to ignore background processes and system overlays
local ignored_classes = {
    "WorkerW", "Progman", "Shell_TrayWnd", "HyprWinOverlay",
    "Chrome_ChildWin_Templ", "GhostWindow", "DesktopWindowXamlSource", 
    "MSCTFIME UI", "IME", "CicMarshalWnd", "TaskManagerWindow"
}

-- Safe window tracking filter function
function should_ignore(hwnd, title, class)
    -- Самый надежный способ отсечь фоновые процессы Хромиума и Капкута
    if not title or string.trim(title) == "" then return true end
    
    for _, ic in ipairs(ignored_classes) do
        if class == ic then return true end
    end
    return false
end

package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua;./scripts/?/init.lua"

-- Dynamic path mapping for multi-file user configs
local user_path = wm.get_config_path()
local user_dir = user_path:match("(.*[/\\])")
if user_dir then
    package.path = package.path .. ";" .. user_dir .. "?.lua;" .. user_dir .. "?/init.lua"
end

-- УДАЛЕНО: больше не загружаем topbar и control_center
local alttab = require("alttab")
local launcher = require("launcher")
local hl_shim = require("hl_shim")

-- Run the user's entry point config file
local success, err = pcall(dofile, user_path)
if not success then
    log("CONFIG ERROR: " .. tostring(err))
end

-- string.trim уже определен выше на строке 47-49, убираем дубликат

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

local function is_tracked(hwnd)
    for i, w in ipairs(HyprWin.windows) do
        if w == hwnd then return i end
    end
    return nil
end

-- Solve Bezier curves using binary search approximation
local function solve_bezier(p1, p2, t)
    local x1, y1 = p1[1], p1[2]
    local x2, y2 = p2[1], p2[2]

    local function get_pt(n1, n2, tv)
        return 3 * (1 - tv)^2 * tv * n1 + 3 * (1 - tv) * tv^2 * n2 + tv^3
    end

    local low, high = 0.0, 1.0
    local guess = t
    for _ = 1, 16 do
        local cur = get_pt(x1, x2, guess)
        if math.abs(cur - t) < 0.0005 then break end
        if cur < t then low = guess else high = guess end
        guess = (low + high) * 0.5
    end

    return get_pt(y1, y2, guess)
end

local function solve_spring(curr, vel, target, stiffness, dampening, mass, dt)
    if dt <= 0 then return curr, vel end
    if math.abs(curr - target) < 0.5 and math.abs(vel) < 0.5 then
        return target, 0
    end

    dt = math.min(dt, 0.05)
    local steps = 4
    local sdt = dt / steps
    for _ = 1, steps do
        local force = -stiffness * (curr - target) - dampening * vel
        vel = vel + (force / mass) * sdt
        curr = curr + vel * sdt
    end
    return curr, vel
end

-- Helper to retrieve spring parameters for an animation leaf
local function get_spring_params(leaf)
    if HyprWin.anim_active == false then
        return nil
    end

    local stiffness, dampening, mass = 140, 18, 1.0
    local speed = 8
    local anim = HyprWin.animations and (HyprWin.animations[leaf] or HyprWin.animations["windows"] or HyprWin.animations["global"])
    if anim then
        if anim.enabled == false then
            return nil
        end
        speed = anim.speed or speed
        local spring_name = anim.spring
        if spring_name and HyprWin.curves and HyprWin.curves[spring_name] then
            local curve = HyprWin.curves[spring_name]
            if curve.type == "spring" then
                stiffness = curve.stiffness or stiffness
                dampening = curve.dampening or dampening
                mass = curve.mass or mass
            end
        elseif anim.bezier and HyprWin.curves and HyprWin.curves[anim.bezier] then
            stiffness = 150
            dampening = 20
            mass = 1.0
        end
    end
    return stiffness, dampening, mass, speed
end

-- Tiling layout calculation for a workspace with screen offset (for sliding)
local function layout_workspace(ws, offset_x, offset_y)
    local ws_windows = {}
    for _, hwnd in ipairs(HyprWin.windows) do
        local w_ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        local is_sticky = HyprWin.sticky_windows[hwnd]
        if (w_ws == ws or is_sticky) and not wm.is_minimized(hwnd) and not HyprWin.floating_windows[hwnd] then
            table.insert(ws_windows, hwnd)
        end
    end

    local n = #ws_windows
    if n == 0 then return end

    local sw, sh = wm.get_screen_size()
    local t = HyprWin.theme
    local bar_h = t.bar_height + 5
    local tx, ty = t.gaps_out + offset_x, bar_h + t.gaps_out + offset_y
    local tw, th = sw - (t.gaps_out * 2), sh - bar_h - (t.gaps_out * 2)
    local ratio = HyprWin.workspace_ratios[ws] or 0.5

    local function recursive_tile(x, y, w, h, first, last, depth)
        if first > last then return end
        if first == last then
            local hwnd = ws_windows[first]
            if hwnd then
                HyprWin.window_targets[hwnd] = { x = x, y = y, w = w, h = h }
            end
            return
        end

        local mid = math.floor((first + last) / 2)
        local cur_r = (depth == 0) and ratio or 0.5

        if w > h then
            local w1 = math.floor((w - t.gaps_in) * cur_r)
            recursive_tile(x, y, w1, h, first, mid, depth + 1)
            recursive_tile(x + w1 + t.gaps_in, y, w - w1 - t.gaps_in, h, mid + 1, last, depth + 1)
        else
            local h1 = math.floor((h - t.gaps_in) * cur_r)
            recursive_tile(x, y, w, h1, first, mid, depth + 1)
            recursive_tile(x, y + h1 + t.gaps_in, w, h - h1 - t.gaps_in, mid + 1, last, depth + 1)
        end
    end

    local mode = HyprWin.workspace_rules[ws] or HyprWin.layout_mode
    if mode == "master" and n > 1 then
        local master_w = math.floor((tw - t.gaps_in) * ratio)
        local stack_w = tw - master_w - t.gaps_in
        HyprWin.window_targets[ws_windows[1]] = { x = tx, y = ty, w = master_w, h = th }
        local sn = n - 1
        local sh_step = math.floor((th - t.gaps_in * (sn - 1)) / sn)
        for i = 2, n do
            local sy = ty + (i - 2) * (sh_step + t.gaps_in)
            local cur_h = (i == n) and (th - (sy - ty)) or sh_step
            HyprWin.window_targets[ws_windows[i]] = { x = tx + master_w + t.gaps_in, y = sy, w = stack_w, h = cur_h }
        end
    else
        recursive_tile(tx, ty, tw, th, 1, n, 0)
    end
end

-- Workspace switch trigger supporting slide transitions
local function switch_workspace(target_ws)
    if target_ws == HyprWin.current_workspace and not HyprWin.ws_transition then return end

    local old_ws = HyprWin.current_workspace
    local duration = 0.25

    local start_p = 0.0
    if HyprWin.ws_transition and HyprWin.ws_transition.new == old_ws and HyprWin.ws_transition.old == target_ws then
        start_p = math.max(0.0, 1.0 - (HyprWin.ws_transition.progress or 0.0))
    end

    HyprWin.ws_transition = {
        old = old_ws,
        new = target_ws,
        start_time = os.clock() - (start_p * duration),
        duration = duration,
        direction = (target_ws > old_ws) and 1 or -1,
        progress = start_p
    }

    HyprWin.current_workspace = target_ws
    HyprWin.retile()
end
HyprWin.switch_workspace = switch_workspace

-- Initialize state engines for smooth curves
HyprWin.anim_states = {
    bar = { current = -40, start_val = -40, target = -40, start_time = 0, duration = 0.35, curve = "easeOutQuint" },
    launcher = { current = 0, start_val = 0, target = 0, start_time = 0, duration = 0.28, curve = "md3_decel" }
}

-- Calculate animated progress on the fly using active configuration curves
local function update_animation(name, target_val)
    local anim = HyprWin.anim_states[name]
    if anim.target ~= target_val then
        anim.start_val = anim.current
        anim.target = target_val
        anim.start_time = os.clock()
    end
    
    local elapsed = os.clock() - anim.start_time
    local progress = math.min(1.0, elapsed / anim.duration)
    
    -- Default ease-out curve fallback
    local p1, p2 = { 0.25, 0.1 }, { 0.25, 1.0 }
    if anim.curve and HyprWin.curves and HyprWin.curves[anim.curve] then
        local curve = HyprWin.curves[anim.curve]
        if curve.type == "bezier" and curve.points then
            p1, p2 = curve.points[1], curve.points[2]
        end
    end
    
    local solved = solve_bezier(p1, p2, progress)
    anim.current = anim.start_val + (anim.target - anim.start_val) * solved
    return anim.current
end

-- Apply advanced sizing and placement window rules
local function apply_window_rules(hwnd, title, class)
    if not HyprWin.window_rules then return end
    
    -- Simple flat float match
    local should_float = false
    for _, pattern in ipairs(HyprWin.window_rules.float or {}) do
        if class:match(pattern) or title:match(pattern) then
            should_float = true
            break
        end
    end
    
    if should_float then
        HyprWin.floating_windows[hwnd] = true
        local x, y, w, h = wm.get_window_rect(hwnd)
        HyprWin.floating_rects[hwnd] = { x, y, w, h }
    end

    -- Evaluate advanced rules with screen size math expressions (like monitor_w * 0.48)
    for _, rule in ipairs(HyprWin.window_rules.rules_list or {}) do
        local m_class = rule.match and rule.match.class
        local m_title = rule.match and rule.match.title
        
        local is_match = false
        if m_class and class:match(m_class) then is_match = true end
        if m_title and title:match(m_title) then is_match = true end
        
        if is_match then
            if rule.float then
                HyprWin.floating_windows[hwnd] = true
            end
            
            if rule.size then
                local sw, sh = wm.get_screen_size()
                local target_w = sw * 0.48
                local target_h = sh * 0.50
                
                -- Parse expressions dynamically
                if type(rule.size[1]) == "string" then
                    local expr = rule.size[1]:gsub("monitor_w", tostring(sw))
                    target_w = load("return " .. expr)() or target_w
                else
                    target_w = rule.size[1]
                end
                
                if type(rule.size[2]) == "string" then
                    local expr = rule.size[2]:gsub("monitor_h", tostring(sh))
                    target_h = load("return " .. expr)() or target_h
                else
                    target_h = rule.size[2]
                end
                
                local rx, ry = math.floor((sw - target_w)/2), math.floor((sh - target_h)/2)
                if rule.move then
                    rx = tonumber(rule.move[1]) or rx
                    ry = tonumber(rule.move[2]) or ry
                end
                
                HyprWin.floating_rects[hwnd] = { rx, ry, target_w, target_h }
                wm.move_window(hwnd, rx, ry, target_w, target_h)
            end
        end
    end
end

HyprWin.update_opacities = function()
    local t = HyprWin.theme
    if not t.active_opacity or not t.inactive_opacity then return end
    
    for _, hwnd in ipairs(HyprWin.windows) do
        local class = wm.get_class_name(hwnd)
        -- Пропускаем наши системные окна оверлея и топбара, чтобы случайно их не загасить
        if class ~= "HyprWinOverlay" and class ~= "HyprWinTopbar" then
            if hwnd == HyprWin.focused_window then
                wm.set_window_opacity(hwnd, t.active_opacity)
            else
                wm.set_window_opacity(hwnd, t.inactive_opacity)
            end
        end
    end
end

HyprWin.retile = function()
    if is_retiling then return end
    is_retiling = true

    local function cleanup() is_retiling = false end

    local success, err = xpcall(function()
        local valid = {}
        for _, hwnd in ipairs(HyprWin.windows) do
            if wm.is_window_visible(hwnd) and not wm.is_topmost(hwnd) then
                table.insert(valid, hwnd)
            end
        end
        HyprWin.windows = valid

        for _, hwnd in ipairs(HyprWin.windows) do
            if not HyprWin.window_workspaces[hwnd] then
                HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            end
        end

        for _, hwnd in ipairs(HyprWin.windows) do
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            local is_sticky = HyprWin.sticky_windows[hwnd]
            local is_active = (ws == HyprWin.current_workspace)
            local in_trans = HyprWin.ws_transition and (ws == HyprWin.ws_transition.old or ws == HyprWin.ws_transition.new)

            if not (is_active or is_sticky or in_trans) then
                local rx, ry, rw, rh = wm.get_window_rect(hwnd)
                if rx > -10000 and ry > -10000 then
                    HyprWin.floating_rects[hwnd] = { rx, ry, rw, rh }
                    wm.move_window(hwnd, -32000, -32000, rw, rh)
                end
                HyprWin.window_targets[hwnd] = nil
            elseif HyprWin.floating_windows[hwnd] then
                local saved = HyprWin.floating_rects[hwnd]
                local rx, ry = wm.get_window_rect(hwnd)
                if rx < -10000 and saved then
                    wm.move_window(hwnd, saved[1], saved[2], saved[3], saved[4])
                end
                HyprWin.window_targets[hwnd] = nil
            end
        end

        local sw, sh = wm.get_screen_size()
        local t = HyprWin.theme
        local bar_h = t.bar_height + 5
        local tx, ty = t.gaps_out, bar_h + t.gaps_out
        local tw, th = sw - (t.gaps_out * 2), sh - bar_h - (t.gaps_out * 2)

        local fullscreen_hwnd = nil
        for _, hwnd in ipairs(HyprWin.windows) do
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            if (ws == HyprWin.current_workspace or HyprWin.sticky_windows[hwnd]) and HyprWin.fullscreen_windows[hwnd] then
                fullscreen_hwnd = hwnd
                break
            end
        end

        if fullscreen_hwnd then
            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if ws == HyprWin.current_workspace and not HyprWin.floating_windows[hwnd] then
                    if hwnd == fullscreen_hwnd then
                        HyprWin.window_targets[hwnd] = { x = tx, y = ty, w = tw, h = th }
                    else
                        local _, _, rw, rh = wm.get_window_rect(hwnd)
                        wm.move_window(hwnd, -32000, -32000, rw, rh)
                        HyprWin.window_targets[hwnd] = nil
                    end
                end
            end
            return
        end

        layout_workspace(HyprWin.current_workspace, 0, 0)
        HyprWin.update_opacities()
    end, debug.traceback)

    cleanup()
    if not success then log("RETILE ERROR: " .. tostring(err)) end
end

HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
        if not is_tracked(hwnd) and is_valid(hwnd) and wm.is_toplevel(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            HyprWin.retile()
        end
        return
    end

    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) and wm.is_toplevel(hwnd) then
            local x, y, w, h = wm.get_window_rect(hwnd)
            HyprWin.original_rects[hwnd] = { x, y, w, h }
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            apply_window_rules(hwnd, title, class)
            HyprWin.retile()
        end
        return
    end

    if event_type == 0x8001 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            HyprWin.window_targets[hwnd] = nil
            HyprWin.window_currents[hwnd] = nil
            HyprWin.floating_rects[hwnd] = nil
            if HyprWin.focused_window == hwnd then
                HyprWin.focused_window = nil
            end
            HyprWin.retile()
        end
        return
    end

    if event_type == 0x0016 then
        HyprWin.retile()
    end
end

HyprWin.ui_anims = {
    bar_y = -40,
    launcher_alpha = 0
}

local function lerp(current, target, speed)
    return current + (target - current) * speed
end

local last_frame_time = nil

HyprWin.on_render_overlay = function()
    local time = os.clock()
    local t = HyprWin.theme
    local sw, sh = wm.get_screen_size()

    if not last_frame_time then last_frame_time = time end
    local dt = math.max(0.001, math.min(time - last_frame_time, 0.033))
    last_frame_time = time

    if HyprWin.ws_transition then
        local trans = HyprWin.ws_transition
        local elapsed = time - trans.start_time
        local p = math.min(1.0, elapsed / trans.duration)
        trans.progress = p * (2 - p)

        if p >= 1.0 then
            HyprWin.ws_transition = nil
            HyprWin.retile()
        else
            local dir = trans.direction
            local old_dx = math.floor(-trans.progress * dir * sw)
            local new_dx = math.floor((1.0 - trans.progress) * dir * sw)
            layout_workspace(trans.old, old_dx, 0)
            layout_workspace(trans.new, new_dx, 0)
        end
    end

    local stiffness, dampening, mass, speed = get_spring_params("windows")
    for _, hwnd in ipairs(HyprWin.windows) do
        if not wm.is_minimized(hwnd) and not HyprWin.floating_windows[hwnd] then
            local target = HyprWin.window_targets[hwnd]
            local curr = HyprWin.window_currents[hwnd]

            if target then
                if not curr then
                    curr = { x = target.x, y = target.y, w = target.w, h = target.h, vx = 0, vy = 0, vw = 0, vh = 0 }
                    HyprWin.window_currents[hwnd] = curr
                    wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                elseif stiffness and not HyprWin.ws_transition then
                    local anim_dt = dt * (speed / 6.0)
                    local nx, nvx = solve_spring(curr.x, curr.vx, target.x, stiffness, dampening, mass, anim_dt)
                    local ny, nvy = solve_spring(curr.y, curr.vy, target.y, stiffness, dampening, mass, anim_dt)
                    local nw, nvw = solve_spring(curr.w, curr.vw, target.w, stiffness, dampening, mass, anim_dt)
                    local nh, nvh = solve_spring(curr.h, curr.vh, target.h, stiffness, dampening, mass, anim_dt)

                    if math.abs(nx - curr.x) >= 1 or math.abs(ny - curr.y) >= 1 or 
                       math.abs(nw - curr.w) >= 1 or math.abs(nh - curr.h) >= 1 then
                        wm.move_window(hwnd, nx, ny, nw, nh)
                    end

                    curr.x, curr.vx = nx, nvx
                    curr.y, curr.vy = ny, nvy
                    curr.w, curr.vw = nw, nvw
                    curr.h, curr.vh = nh, nvh
                else
                    curr.x, curr.y, curr.w, curr.h = target.x, target.y, target.w, target.h
                    curr.vx, curr.vy, curr.vw, curr.vh = 0, 0, 0, 0
                    wm.move_window(hwnd, target.x, target.y, target.w, target.h)
                end
            end
        end
    end

    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        local is_sticky = HyprWin.sticky_windows[hwnd]
        local is_active = (ws == HyprWin.current_workspace)
        local in_trans = HyprWin.ws_transition and (ws == HyprWin.ws_transition.old or ws == HyprWin.ws_transition.new)

        if (is_active or is_sticky or in_trans) and not wm.is_minimized(hwnd) then
            local x, y, w, h
            local curr = HyprWin.window_currents[hwnd]
            if curr and not HyprWin.floating_windows[hwnd] then
                x, y, w, h = curr.x, curr.y, curr.w, curr.h
            else
                x, y, w, h = wm.get_window_rect(hwnd)
            end

            if x > -10000 and y > -10000 and x < sw and y < sh then
                local act = t.active_border_color
                local inact = t.border_color

                if hwnd == HyprWin.focused_window then
                    ui.draw_rounded_rect(x, y, w, h, t.rounding, act[1], act[2], act[3], act[4], t.border_size)
                elseif inact and inact[4] > 0 then
                    ui.draw_rounded_rect(x, y, w, h, t.rounding, inact[1], inact[2], inact[3], inact[4], t.border_size)
                end
            end
        end
    end

    alttab.draw()
    launcher.draw(HyprWin.ui_anims.launcher_alpha)
end

-- Initial scanning loop
local existing = wm.enumerate_windows()
local filtered = {}
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        table.insert(filtered, hwnd)
        HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
        apply_window_rules(hwnd, title, class)
    end
end

function find_neighbor(dir)
    local focused = HyprWin.focused_window
    if not focused then return nil end

    local fx, fy, fw, fh = wm.get_window_rect(focused)
    local fcx = fx + fw / 2
    local fcy = fy + fh / 2

    local best_hwnd = nil
    local best_dist = math.huge

    for _, hwnd in ipairs(HyprWin.windows) do
        if hwnd ~= focused and not HyprWin.floating_windows[hwnd] then
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            if ws == HyprWin.current_workspace then
                local x, y, w, h = wm.get_window_rect(hwnd)
                local cx = x + w / 2
                local cy = y + h / 2

                local valid = (dir == "left"  and cx < fcx)
                           or (dir == "right" and cx > fcx)
                           or (dir == "up"    and cy < fcy)
                           or (dir == "down"  and cy > fcy)

                if valid then
                    local dist = math.abs(cx - fcx) + math.abs(cy - fcy)
                    if dist < best_dist then
                        best_dist = dist
                        best_hwnd = hwnd
                    end
                end
            end
        end
    end

    return best_hwnd
end

function focus_direction(dir)
    local target = find_neighbor(dir)
    if target then wm.focus_window(target) end
end

function swap_direction(dir)
    local focused = HyprWin.focused_window
    if not focused then return end

    -- If focused window is floating, slide it physically instead of swapping
    if HyprWin.floating_windows[focused] then
        local x, y, w, h = wm.get_window_rect(focused)
        local step = 50
        if dir == "left" then x = x - step
        elseif dir == "right" then x = x + step
        elseif dir == "up" then y = y - step
        elseif dir == "down" then y = y + step
        end
        wm.move_window(focused, x, y, w, h)
        HyprWin.floating_rects[focused] = { x, y, w, h }
        HyprWin.window_rects[focused] = { x, y, w, h }
        return
    end

    local target  = find_neighbor(dir)
    if not target then return end

    local idx1, idx2 = nil, nil
    for i, hwnd in ipairs(HyprWin.windows) do
        if hwnd == focused then idx1 = i end
        if hwnd == target  then idx2 = i end
    end

    if idx1 and idx2 then
        HyprWin.windows[idx1], HyprWin.windows[idx2] = HyprWin.windows[idx2], HyprWin.windows[idx1]
        HyprWin.retile()
    end
end

-- НОВОЕ: Window groups функции
function create_group()
    local focused = HyprWin.focused_window
    if not focused then return end

    local group_id = HyprWin.next_group_id
    HyprWin.next_group_id = HyprWin.next_group_id + 1

    HyprWin.window_groups[group_id] = { focused }
    HyprWin.window_to_group[focused] = group_id
    HyprWin.active_in_group[group_id] = focused

    log("Created group " .. group_id .. " with window 0x" .. string.format("%X", focused))
end

function add_to_group()
    local focused = HyprWin.focused_window
    if not focused then return end

    -- Найти соседнее окно, которое в группе
    local neighbor = find_neighbor("left") or find_neighbor("right") or
                     find_neighbor("up") or find_neighbor("down")

    if not neighbor then return end

    local group_id = HyprWin.window_to_group[neighbor]
    if not group_id then
        -- Создаём новую группу с соседом
        group_id = HyprWin.next_group_id
        HyprWin.next_group_id = HyprWin.next_group_id + 1
        HyprWin.window_groups[group_id] = { neighbor }
        HyprWin.window_to_group[neighbor] = group_id
        HyprWin.active_in_group[group_id] = neighbor
    end

    -- Добавляем focused в группу
    table.insert(HyprWin.window_groups[group_id], focused)
    HyprWin.window_to_group[focused] = group_id

    log("Added window 0x" .. string.format("%X", focused) .. " to group " .. group_id)
    HyprWin.retile()
end

function cycle_group(direction)
    local focused = HyprWin.focused_window
    if not focused then return end

    local group_id = HyprWin.window_to_group[focused]
    if not group_id then return end

    local group = HyprWin.window_groups[group_id]
    if not group or #group <= 1 then return end

    local current_idx = nil
    for i, hwnd in ipairs(group) do
        if hwnd == focused then
            current_idx = i
            break
        end
    end

    if not current_idx then return end

    local next_idx
    if direction == "next" then
        next_idx = (current_idx % #group) + 1
    else
        next_idx = current_idx - 1
        if next_idx < 1 then next_idx = #group end
    end

    local next_hwnd = group[next_idx]
    HyprWin.active_in_group[group_id] = next_hwnd
    wm.focus_window(next_hwnd)
    log("Cycled to window " .. next_idx .. " in group " .. group_id)
end

function remove_from_group()
    local focused = HyprWin.focused_window
    if not focused then return end

    local group_id = HyprWin.window_to_group[focused]
    if not group_id then return end

    local group = HyprWin.window_groups[group_id]
    for i, hwnd in ipairs(group) do
        if hwnd == focused then
            table.remove(group, i)
            break
        end
    end

    HyprWin.window_to_group[focused] = nil

    -- Если группа пустая, удаляем её
    if #group == 0 then
        HyprWin.window_groups[group_id] = nil
        HyprWin.active_in_group[group_id] = nil
    elseif HyprWin.active_in_group[group_id] == focused then
        HyprWin.active_in_group[group_id] = group[1]
    end

    log("Removed window 0x" .. string.format("%X", focused) .. " from group " .. group_id)
    HyprWin.retile()
end

-- Fallback hotkey registration for legacy hardcoded bindings
HyprWin.on_hotkey = function(id)
    -- Сначала проверяем, есть ли такой кастомный бинд из hl_shim
    if HyprWin.custom_hotkeys and HyprWin.custom_hotkeys[id] then
        local callback = HyprWin.custom_hotkeys[id]
        if type(callback) == "function" then
            callback()
        end
        return
    end

    -- Если кастомного нет, пускаем по дефолтной цепочке
    if id >= 101 and id <= 109 then
        local target_ws = id - 100
        switch_workspace(target_ws)
    elseif id >= 201 and id <= 209 then
        local target_ws = id - 200
        local focused = HyprWin.focused_window
        if focused then
            HyprWin.window_workspaces[focused] = target_ws
            HyprWin.retile()
        end
    elseif id == 302 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.sticky_windows[focused] then
                HyprWin.sticky_windows[focused] = nil
                log("Window 0x" .. string.format("%X", focused) .. " is now UNSTICKY")
            else
                HyprWin.sticky_windows[focused] = true
                HyprWin.floating_windows[focused] = true
                log("Window 0x" .. string.format("%X", focused) .. " is now STICKY (visible on all workspaces)")
            end
            HyprWin.retile()
        end
    elseif id == 303 then
        local active_hwnd = wm.get_foreground_window()
        if active_hwnd and active_hwnd ~= 0 then
            wm.force_enable_resize(active_hwnd)
            if not is_tracked(active_hwnd) then
                table.insert(HyprWin.windows, active_hwnd)
                HyprWin.window_workspaces[active_hwnd] = HyprWin.current_workspace
            end
            HyprWin.floating_windows[active_hwnd] = nil
            HyprWin.retile()
        end
    elseif id == 304 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.fullscreen_windows[focused] then
                HyprWin.fullscreen_windows[focused] = nil
            else
                HyprWin.fullscreen_windows[focused] = true
            end
            HyprWin.retile()
        end
    elseif id == 305 then
        launcher.toggle()
    elseif id == 306 then
        launcher.commit()
    elseif id == 401 then
        focus_direction("left")
    elseif id == 402 then
        if HyprWin.launcher_active then
            launcher.navigate("down")
        else
            focus_direction("down")
        end
    elseif id == 403 then
        if HyprWin.launcher_active then
            launcher.navigate("up")
        else
            focus_direction("up")
        end
    elseif id == 404 then
        focus_direction("right")
    elseif id == 501 then
        swap_direction("left")
    elseif id == 502 then
        swap_direction("down")
    elseif id == 503 then
        swap_direction("up")
    elseif id == 504 then
        swap_direction("right")
    elseif id == 601 or id == 603 then
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio > 0.15 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio - 0.05
            HyprWin.retile()
        end
    elseif id == 602 or id == 604 then
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio < 0.85 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio + 0.05
            HyprWin.retile()
        end
    end
end

HyprWin.cc_state = HyprWin.cc_state or {
    wifi = true,
    bluetooth = false,
    nightlight = false,
    focus = false,
    volume = 0.7,
    brightness = 0.7
}

-- УДАЛЕНО: весь код on_click (более 100 строк с control center логикой)

HyprWin.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

HyprWin.on_ipc_request = function(req)
    log("IPC Request received: " .. tostring(req))
    if not req or req == "" then return "ERROR: Empty command" end
    
    -- Trim whitespace
    req = req:gsub("^%s*(.-)%s*$", "%1")
    
    local parts = {}
    for part in string.gmatch(req, "[^%s]+") do
        table.insert(parts, part)
    end
    
    if #parts == 0 then return "ERROR: Empty command" end
    
    local cmd = parts[1]:lower()
    
    if cmd == "dispatch" then
        local disp_name = parts[2]
        if not disp_name then return "ERROR: Missing dispatcher name" end
        
        -- Join remaining arguments
        local args = {}
        for i = 3, #parts do
            table.insert(args, parts[i])
        end
        local args_str = table.concat(args, " ")
        
        local success, err = pcall(function()
            if disp_name == "workspace" then
                hl.dsp.workspace(args_str)()
            elseif disp_name == "movetoworkspace" then
                hl.dsp.movetoworkspace(args_str)()
            elseif disp_name == "exec" then
                hl.dsp.exec_cmd(args_str)()
            elseif disp_name == "togglefloating" then
                hl.dsp.window.float()()
            elseif disp_name == "fullscreen" then
                hl.dsp.window.fullscreen()()
            elseif disp_name == "killactive" then
                hl.dsp.window.close()()
            elseif disp_name == "movefocus" then
                hl.dsp.focus({ direction = args_str:lower() })()
            elseif disp_name == "swapwindow" then
                hl.dsp.window.move({ direction = args_str:lower() })()
            else
                error("Unsupported dispatcher: " .. disp_name)
            end
        end)
        
        if success then
            return "OK"
        else
            return "ERROR: " .. tostring(err)
        end
        
    elseif cmd == "activewindow" then
        local focused = HyprWin.focused_window
        if not focused then return "None" end
        local title = wm.get_window_title(focused)
        local class = wm.get_class_name(focused)
        return string.format("HWND: 0x%X\nClass: %s\nTitle: %s", focused, class, title)
        
    elseif cmd == "clients" then
        local lines = {}
        for _, hwnd in ipairs(HyprWin.windows) do
            local title = wm.get_window_title(hwnd)
            local class = wm.get_class_name(hwnd)
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            local is_float = HyprWin.floating_windows[hwnd] and "floating" or "tiled"
            table.insert(lines, string.format("0x%X -> Workspace %s (%s) [%s]: %s", hwnd, ws, is_float, class, title))
        end
        return table.concat(lines, "\n")

    elseif cmd == "setprop" then
        -- Ожидаемый формат: setprop <activewindow/HWND> <property> <value>
        -- Пример: setprop activewindow opacity 0.8
        local target_win = parts[2]
        local prop = parts[3]
        local val = parts[4]

        if not target_win or not prop or not val then
            return "ERROR: Usage: setprop <activewindow/HWND> <property> <value>"
        end

        local hwnd = nil
        if target_win:lower() == "activewindow" then
            hwnd = HyprWin.focused_window
        else
            hwnd = tonumber(target_win) or tonumber(target_win, 16)
        end

        if not hwnd then return "ERROR: Invalid window reference" end

        if prop:lower() == "opacity" then
            local opacity_val = tonumber(val)
            if not opacity_val or opacity_val < 0.1 or opacity_val > 1.0 then
                return "ERROR: Opacity must be between 0.1 and 1.0"
            end
            -- Меняем прозрачность конкретного окна на лету
            wm.set_window_opacity(hwnd, opacity_val)
            return "OK"
        else
            return "ERROR: Unsupported property: " .. prop
        end
    else
        return "ERROR: Unknown command: " .. cmd
    end
end

HyprWin.windows = filtered
HyprWin.retile()