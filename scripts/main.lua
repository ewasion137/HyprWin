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
    if title == "" and class == "" then return true end
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

local topbar = require("topbar")
local alttab = require("alttab")
local launcher = require("launcher")
local hl_shim = require("hl_shim")

-- Run the user's entry point config file
local success, err = pcall(dofile, user_path)
if not success then
    log("CONFIG ERROR: " .. tostring(err))
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

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
    
    local function get_pt(n1, n2, t_val)
        return 3 * (1 - t_val)^2 * t_val * n1 + 3 * (1 - t_val) * t_val^2 * n2 + t_val^3
    end
    
    local low, high = 0.0, 1.0
    local guess = t
    for i = 1, 8 do
        local current_x = get_pt(x1, x2, guess)
        if math.abs(current_x - t) < 0.001 then
            break
        elseif current_x < t then
            low = guess
        else
            high = guess
        end
        guess = (low + high) / 2
    end
    
    return get_pt(y1, y2, guess)
end

-- Spring physics solver using Euler integration with sub-stepping
local function solve_spring(curr, vel, target, stiffness, dampening, mass, dt)
    if dt <= 0 then return curr, vel end
    dt = math.min(dt, 0.1) -- Limit dt to prevent instability on extreme drops
    local steps = 8
    local sdt = dt / steps
    for i = 1, steps do
        local dx = curr - target
        local force = -stiffness * dx - dampening * vel
        local accel = force / mass
        vel = vel + accel * sdt
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

    local current_ratio = HyprWin.workspace_ratios[ws] or 0.5

    local function recursive_tile(x, y, w, h, first, last, depth)
        depth = depth or 0
        if first > last then return end
        if first == last then
            local hwnd = ws_windows[first]
            if hwnd then
                HyprWin.window_targets[hwnd] = { x = x, y = y, w = w, h = h }
            end
            return
        end

        local mid = math.floor((first + last) / 2)
        local ratio = (depth == 0) and current_ratio or 0.5

        if w > h then
            local w1 = math.floor((w - t.gaps_in) * ratio)
            recursive_tile(x, y, w1, h, first, mid, depth + 1)
            recursive_tile(x + w1 + t.gaps_in, y, w - w1 - t.gaps_in, h, mid + 1, last, depth + 1)
        else
            local h1 = math.floor((h - t.gaps_in) * ratio)
            recursive_tile(x, y, w, h1, first, mid, depth + 1)
            recursive_tile(x, y + h1 + t.gaps_in, w, h - h1 - t.gaps_in, mid + 1, last, depth + 1)
        end
    end

    local active_layout = HyprWin.workspace_rules[ws] or HyprWin.layout_mode

    if active_layout == "bsp" then
        recursive_tile(tx, ty, tw, th, 1, n, 0)
    elseif active_layout == "master" then
        if n == 1 then
            HyprWin.window_targets[ws_windows[1]] = { x = tx, y = ty, w = tw, h = th }
        else
            local master_w = math.floor((tw - t.gaps_in) * current_ratio)
            local stack_w = tw - master_w - t.gaps_in
            HyprWin.window_targets[ws_windows[1]] = { x = tx, y = ty, w = master_w, h = th }
            local stack_n = n - 1
            local stack_h = math.floor((th - t.gaps_in * (stack_n - 1)) / stack_n)
            for i = 2, n do
                local sy = ty + (i - 2) * (stack_h + t.gaps_in)
                local sh = (i == n) and (th - (sy - ty)) or stack_h
                HyprWin.window_targets[ws_windows[i]] = { x = tx + master_w + t.gaps_in, y = sy, w = stack_w, h = sh }
            end
        end
    end
end

-- Workspace switch trigger supporting slide transitions
local function switch_workspace(target_ws)
    if target_ws == HyprWin.current_workspace then return end
    
    local old_ws = HyprWin.current_workspace
    HyprWin.current_workspace = target_ws
    
    local ws_anim = HyprWin.animations and (HyprWin.animations["workspaces"] or HyprWin.animations["global"])
    if ws_anim and ws_anim.enabled ~= false and HyprWin.anim_active ~= false then
        local duration = 0.35
        if ws_anim.speed and ws_anim.speed > 0 then
            duration = 3.0 / ws_anim.speed
        end
        HyprWin.ws_transition = {
            old = old_ws,
            new = target_ws,
            start_time = os.clock(),
            duration = duration,
            style = ws_anim.style or "slide",
            direction = (target_ws > old_ws) and 1 or -1
        }
    else
        HyprWin.ws_transition = nil
    end
    
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

HyprWin.retile = function()
    if is_retiling then return end
    is_retiling = true

    local success, err = pcall(function()
        local valid_windows = {}
        for _, hwnd in ipairs(HyprWin.windows) do
            if wm.is_window_visible(hwnd) and not wm.is_topmost(hwnd) then
                table.insert(valid_windows, hwnd)
            end
        end
        HyprWin.windows = valid_windows

        for _, hwnd in ipairs(HyprWin.windows) do
            if not HyprWin.window_workspaces[hwnd] then
                HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            end
            if HyprWin.floating_windows[hwnd] then
                HyprWin.window_targets[hwnd] = nil
                HyprWin.window_currents[hwnd] = nil
            end
        end

        local fullscreen_hwnd = nil
        for _, hwnd in ipairs(HyprWin.windows) do
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            local is_sticky = HyprWin.sticky_windows[hwnd]
            local is_active_ws = (ws == HyprWin.current_workspace)
            local is_special = (ws == HyprWin.active_special_workspace)

            local in_transition = false
            if HyprWin.ws_transition and (ws == HyprWin.ws_transition.old or ws == HyprWin.ws_transition.new) then
                in_transition = true
            end

            if is_active_ws or is_sticky or is_special or in_transition then
                if not wm.is_minimized(hwnd) then
                    if HyprWin.fullscreen_windows[hwnd] then
                        fullscreen_hwnd = hwnd
                    end

                    if is_special then
                        HyprWin.floating_windows[hwnd] = true
                    end

                    if not HyprWin.floating_windows[hwnd] then
                    else
                        local rect = HyprWin.window_rects[hwnd]
                        if (rect and (rect[1] < -10000 or rect[2] < -10000)) or is_special then
                            local saved = HyprWin.floating_rects[hwnd]
                            if is_special and not saved then
                                local sw, sh = wm.get_screen_size()
                                saved = { math.floor(sw * 0.15), math.floor(sh * 0.15), math.floor(sw * 0.70), math.floor(sh * 0.70) }
                                HyprWin.floating_rects[hwnd] = saved
                            end
                            saved = saved or { 150, 150, 1280, 720 }
                            wm.move_window(hwnd, saved[1], saved[2], saved[3], saved[4])
                            HyprWin.window_rects[hwnd] = saved
                        end
                    end
                end
            else
                if HyprWin.floating_windows[hwnd] then
                    local rect = HyprWin.window_rects[hwnd]
                    if rect and rect[1] >= -10000 and rect[2] >= -10000 then
                        HyprWin.floating_rects[hwnd] = rect
                    end
                end
                wm.move_window(hwnd, -32000, -32000, 800, 600)
                HyprWin.window_rects[hwnd] = { -32000, -32000, 800, 600 }
                HyprWin.window_targets[hwnd] = nil
                HyprWin.window_currents[hwnd] = nil
            end
        end

        local sw, sh = wm.get_screen_size()
        local t = HyprWin.theme
        local bar_h = t.bar_height + 5
        
        local tx, ty = t.gaps_out, bar_h + t.gaps_out
        local tw, th = sw - (t.gaps_out * 2), sh - bar_h - (t.gaps_out * 2)

        if fullscreen_hwnd then
            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if (ws == HyprWin.current_workspace) and not HyprWin.floating_windows[hwnd] then
                    if hwnd == fullscreen_hwnd then
                        HyprWin.window_targets[hwnd] = { x = tx, y = ty, w = tw, h = th }
                    else
                        wm.move_window(hwnd, -32000, -32000, 800, 600)
                        HyprWin.window_targets[hwnd] = nil
                        HyprWin.window_currents[hwnd] = nil
                    end
                end
            end
            return
        end

        if HyprWin.ws_transition then
            local trans = HyprWin.ws_transition
            local solved = trans.solved or 0.0
            local dir = trans.direction

            local old_offset_x, old_offset_y = 0, 0
            local new_offset_x, new_offset_y = 0, 0

            if trans.style == "slidevert" then
                old_offset_y = -solved * dir * sh
                new_offset_y = (1 - solved) * dir * sh
            else
                old_offset_x = -solved * dir * sw
                new_offset_x = (1 - solved) * dir * sw
            end

            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if ws ~= trans.old and ws ~= trans.new and not HyprWin.sticky_windows[hwnd] then
                    HyprWin.window_targets[hwnd] = nil
                end
            end

            layout_workspace(trans.old, old_offset_x, old_offset_y)
            layout_workspace(trans.new, new_offset_x, new_offset_y)
        else
            for _, hwnd in ipairs(HyprWin.windows) do
                local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
                if ws ~= HyprWin.current_workspace and not HyprWin.sticky_windows[hwnd] then
                    HyprWin.window_targets[hwnd] = nil
                end
            end
            layout_workspace(HyprWin.current_workspace, 0, 0)
        end
    end)

    is_retiling = false
    if not success then
        log("RETILING ERROR: " .. tostring(err))
    end
end

HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
        if not is_tracked(hwnd) and is_valid(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            HyprWin.retile()
        end
        return
    end

    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) then
            local x, y, w, h = wm.get_window_rect(hwnd)
            HyprWin.original_rects[hwnd] = { x, y, w, h }

            table.insert(HyprWin.windows, hwnd)
            local ws = HyprWin.current_workspace
            HyprWin.window_workspaces[hwnd] = ws
            
            -- Set creation flag for entrance animation
            HyprWin.new_windows[hwnd] = true

            -- Trigger rules parser!
            apply_window_rules(hwnd, title, class)
        end
        HyprWin.retile()
    end

    if event_type == 0x8001 or event_type == 0x8003 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            if HyprWin.focused_window == hwnd then
                HyprWin.focused_window = nil
            end
            HyprWin.retile()
        end
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

    -- Track frame delta (dt)
    if not last_frame_time then last_frame_time = time end
    local dt = time - last_frame_time
    last_frame_time = time

    -- Update workspace transition if active
    if HyprWin.ws_transition then
        local elapsed = time - HyprWin.ws_transition.start_time
        local progress = math.min(1.0, elapsed / HyprWin.ws_transition.duration)
        local solved = progress * (2 - progress) -- Quadratic ease-out

        HyprWin.ws_transition.solved = solved
        if progress >= 1.0 then
            HyprWin.ws_transition = nil
        end
        -- Trigger retiling to update target positions of sliding windows
        HyprWin.retile()
    end

    -- Run spring physics solver for window movement
    local stiffness, dampening, mass, speed = get_spring_params("windows")
    if stiffness then
        local speed_factor = speed / 6.0
        local anim_dt = dt * speed_factor
        for _, hwnd in ipairs(HyprWin.windows) do
            if not wm.is_minimized(hwnd) then
                local target = HyprWin.window_targets[hwnd]
                local curr = HyprWin.window_currents[hwnd]

                if target then
                    local ax, ay, aw, ah = wm.get_window_rect(hwnd)
                    if not curr or ax < -10000 or ay < -10000 then
                        local start_x = target.x
                        local start_y = target.y
                        
                        if HyprWin.ws_transition then
                            local trans = HyprWin.ws_transition
                            local dir = trans.direction
                            if trans.style == "slidevert" then
                                start_y = target.y + dir * sh
                            else
                                start_x = target.x + dir * sw
                            end
                        elseif HyprWin.new_windows[hwnd] then
                            local style = "slide"
                            local win_in = HyprWin.animations["windowsIn"] or HyprWin.animations["windows"]
                            if win_in and win_in.style then
                                style = win_in.style
                            end
                            
                            if style:match("popin") then
                                local w = target.w * 0.85
                                local h = target.h * 0.85
                                curr = {
                                    x = target.x + (target.w - w)/2,
                                    y = target.y + (target.h - h)/2,
                                    w = w,
                                    h = h,
                                    vx = 0, vy = 0, vw = 0, vh = 0
                                }
                            else -- slide style
                                curr = {
                                    x = target.x,
                                    y = target.y + 200,
                                    w = target.w,
                                    h = target.h,
                                    vx = 0, vy = 0, vw = 0, vh = 0
                                }
                            end
                        end
                        
                        if not curr or ax < -10000 or ay < -10000 then
                            curr = {
                                x = start_x,
                                y = start_y,
                                w = target.w,
                                h = target.h,
                                vx = 0, vy = 0, vw = 0, vh = 0
                            }
                        end
                        
                        HyprWin.window_currents[hwnd] = curr
                        HyprWin.new_windows[hwnd] = nil
                        wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                    end

                    curr.x, curr.vx = solve_spring(curr.x, curr.vx, target.x, stiffness, dampening, mass, anim_dt)
                    curr.y, curr.vy = solve_spring(curr.y, curr.vy, target.y, stiffness, dampening, mass, anim_dt)
                    curr.w, curr.vw = solve_spring(curr.w, curr.vw, target.w, stiffness, dampening, mass, anim_dt)
                    curr.h, curr.vh = solve_spring(curr.h, curr.vh, target.h, stiffness, dampening, mass, anim_dt)

                    wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                else
                    if not HyprWin.floating_windows[hwnd] then
                        wm.move_window(hwnd, -32000, -32000, 800, 600)
                    end
                end
            end
        end
    else
        -- Instant tiling fallback
        for _, hwnd in ipairs(HyprWin.windows) do
            local target = HyprWin.window_targets[hwnd]
            if target then
                wm.move_window(hwnd, target.x, target.y, target.w, target.h)
                HyprWin.window_currents[hwnd] = { x = target.x, y = target.y, w = target.w, h = target.h, vx = 0, vy = 0, vw = 0, vh = 0 }
            else
                if not HyprWin.floating_windows[hwnd] then
                    wm.move_window(hwnd, -32000, -32000, 800, 600)
                end
            end
        end
    end

    -- Window Borders drawing directly bound to layout theme tokens
    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        local is_sticky = HyprWin.sticky_windows[hwnd]
        local is_active_ws = (ws == HyprWin.current_workspace)
        local in_transition = false
        if HyprWin.ws_transition and (ws == HyprWin.ws_transition.old or ws == HyprWin.ws_transition.new) then
            in_transition = true
        end

        if (is_active_ws or is_sticky or in_transition) and not wm.is_minimized(hwnd) then
            local x, y, w, h
            if HyprWin.floating_windows[hwnd] then
                x, y, w, h = wm.get_window_rect(hwnd)
            else
                local curr = HyprWin.window_currents[hwnd]
                if curr then
                    x, y, w, h = curr.x, curr.y, curr.w, curr.h
                else
                    x, y, w, h = wm.get_window_rect(hwnd)
                end
            end
            
            -- Only draw borders if window is visible on the screen bounds
            if x > -10000 and y > -10000 and x < sw and y < sh then
                local act = t.active_border_color
                local inact = t.border_color
                if hwnd == HyprWin.focused_window then
                    local glow = 0.1 * math.sin(time * 5)
                    ui.draw_rounded_rect(x-3, y-3, w+6, h+6, t.rounding + 4, act[1], act[2], act[3], 0.2 + glow, 8) 
                    ui.draw_rounded_rect(x, y, w, h, t.rounding, act[1], act[2], act[3], act[4], t.border_size) 
                else
                    if inact and inact[4] > 0 then
                        ui.draw_rounded_rect(x, y, w, h, t.rounding, inact[1], inact[2], inact[3], inact[4], t.border_size) 
                    end
                end
            end
        end
    end

    alttab.draw()
    launcher.draw(HyprWin.ui_anims.launcher_alpha)
end

HyprWin.on_render_topbar = function()
    -- Evaluate math Bezier curves for bar and launcher
    local bar_y = update_animation("bar", 0)
    local launcher_alpha = update_animation("launcher", HyprWin.launcher_active and 1 or 0)
    
    HyprWin.ui_anims.bar_y = lerp(HyprWin.ui_anims.bar_y, 0, HyprWin.anim_speed)
    HyprWin.ui_anims.launcher_alpha = lerp(HyprWin.ui_anims.launcher_alpha, HyprWin.launcher_active and 1 or 0, HyprWin.anim_speed)

    topbar.draw(HyprWin.ui_anims.bar_y)
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
    elseif id == 301 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.floating_windows[focused] then
                -- Возвращаем в тайлинг
                HyprWin.floating_windows[focused] = nil
                HyprWin.sticky_windows[focused] = nil
            else
                -- Переводим во Float
                HyprWin.floating_windows[focused] = true
                
                -- Возвращаем окну его оригинальный размер до тайлинга (или дефолтный 1280x720)
                local orig = HyprWin.original_rects[focused] or { 150, 150, 1280, 720 }
                local sw, sh = wm.get_screen_size()
                
                local w = orig[3] or 1280
                local h = orig[4] or 720
                local x = math.floor((sw - w) / 2)
                local y = math.floor((sh - h) / 2)
                
                -- Принудительно двигаем его в центр экрана
                wm.move_window(focused, x, y, w, h)
                HyprWin.floating_rects[focused] = { x, y, w, h }
                HyprWin.window_rects[focused] = { x, y, w, h }
            end
            HyprWin.retile()
        end
    elseif id == 302 then
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.sticky_windows[focused] then
                HyprWin.sticky_windows[focused] = nil
            else
                HyprWin.sticky_windows[focused] = true
                HyprWin.floating_windows[focused] = true
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

HyprWin.on_click = function(x, y)
    local sw, _ = wm.get_screen_size()
    local t = HyprWin.theme
    
    -- --- 1. КЛИКИ ВНУТРИ CONTROL CENTER (Если он открыт) ---
    if HyprWin.cc_active then
        local cc_w, cc_h = 320, 400
        local cc_x = sw - cc_w - 16
        local cc_y = t.bar_height + 15 -- Начало CC по высоте (~45)

        if x >= cc_x and x <= cc_x + cc_w and y >= cc_y and y <= cc_y + cc_h then
            -- Переводим координаты в локальные относительно верхнего левого угла CC
            local lx = x - cc_x
            local ly = y - cc_y

            local btn_w, btn_h = (cc_w - 60) / 2, 45

            -- Кнопка Wi-Fi (lx: 20..20+btn_w, ly: 20..20+btn_h)
            if lx >= 20 and lx <= 20 + btn_w and ly >= 20 and ly <= 20 + btn_h then
                log("CC Click: Wi-Fi toggled!")
                -- Сюда потом прикрутим нативный вызов
                return
            end

            -- Кнопка Bluetooth
            if lx >= 30 + btn_w and lx <= 30 + btn_w * 2 and ly >= 20 and ly <= 20 + btn_h then
                log("CC Click: Bluetooth toggled!")
                return
            end

            -- Кнопка Night Light
            if lx >= 20 and lx <= 20 + btn_w and ly >= 75 and ly <= 75 + btn_h then
                log("CC Click: Night Light toggled!")
                return
            end

            -- Кнопка Focus
            if lx >= 30 + btn_w and lx <= 30 + btn_w * 2 and ly >= 75 and ly <= 75 + btn_h then
                log("CC Click: Focus toggled!")
                return
            end

            -- Слайдер Volume (y: 150..185)
            if ly >= 150 and ly <= 185 then
                local pct = math.min(1.0, math.max(0.0, (lx - 20) / (cc_w - 40)))
                log("CC Click: Volume set to " .. math.floor(pct * 100) .. "%")
                -- Сюда добавим нативное управление звуком
                return
            end

            -- Слайдер Brightness (y: 210..245)
            if ly >= 210 and ly <= 245 then
                local pct = math.min(1.0, math.max(0.0, (lx - 20) / (cc_w - 40)))
                log("CC Click: Brightness set to " .. math.floor(pct * 100) .. "%")
                return
            end

            -- Кнопка Power Off (Слева внизу)
            if lx >= 20 and lx <= 120 and ly >= cc_h - 55 and ly <= cc_h - 30 then
                log("CC Click: Shutting down system...")
                wm.spawn("shutdown /s /t 0")
                return
            end

            -- Кнопка Reboot (Справа внизу)
            if lx >= 140 and lx <= 240 and ly >= cc_h - 55 and ly <= cc_h - 30 then
                log("CC Click: Rebooting system...")
                wm.spawn("shutdown /r /t 0")
                return
            end

            return -- Поглощаем любые другие клики внутри коробки CC
        end
    end

    -- --- 2. КЛИКИ ПО САМОМУ ТОПБАРУ ---
    -- Координата шестеренки (Control Center)
    local trigger_x = sw - 16 - 25
    local trigger_y = 8
    
    if x >= trigger_x - 10 and x <= trigger_x + 30 and y >= trigger_y and y <= trigger_y + 30 then
        require("control_center").toggle()
        return
    end
    
    -- Клик по воркспейсам
    local bar_x = 16
    local WS_OFFSET_X = 45
    local WS_SPACING  = 30
    for i = 1, 7 do
        local wx = bar_x + WS_OFFSET_X + (i - 1) * WS_SPACING
        if x >= wx - 5 and x <= wx + 25 then
            HyprWin.switch_workspace(i)
            return
        end
    end
end

HyprWin.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

HyprWin.windows = filtered
HyprWin.retile()