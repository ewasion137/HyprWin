-- scripts/main.lua
HyprWin = {}
HyprWin.windows = {}
HyprWin.focused_window = nil
HyprWin.current_workspace = 1
HyprWin.window_workspaces = {} -- Tracks workspace ID for each hwnd
HyprWin.floating_windows = {}  -- Tracks floating state for each hwnd (boolean)
HyprWin.floating_rects = {}    -- Stores custom geometry {x, y, w, h} for floating windows
HyprWin.sticky_windows = {}    -- Tracks pinned/sticky state (visible on all workspaces)
HyprWin.fullscreen_windows = {} -- Tracks monocle-fullscreen state for each hwnd (boolean)
HyprWin.workspace_ratios = {}  -- Stores split ratio (0.1 - 0.9) for each workspace
HyprWin.layout_mode = "bsp"
HyprWin.window_rects = {} -- Tracks current coordinates {x, y, w, h}
HyprWin.focused_window_title = ""
HyprWin.system_stats = { cpu = 0, ram = 0, last_update = 0 }
HyprWin.anim_speed = 0.15
HyprWin.workspace_roots = {}
local is_retiling = false

package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua;./scripts/?/init.lua"

local topbar = require("topbar")
local alttab = require("alttab")
local launcher = require("launcher")

-- Helper to check if window still exists and is visible
local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

local window_rules = {
    float = { "Telegram", "Picture-in-picture", "Calculator", "Картинка в картинке" },
    ignore_classes = { 
        "Chrome_ChildWin_Templ", "HyprWinOverlay", "GhostWindow", 
        "DesktopWindowXamlSource", "MSCTFIME UI", "IME", "CicMarshalWnd",
        "TaskManagerWindow"
    }
}

local function is_tracked(hwnd)
    for i, w in ipairs(HyprWin.windows) do
        if w == hwnd then return i end
    end
    return nil
end

local function should_ignore(hwnd, title, class)
    title = title or ""
    class = class or ""
    for _, pattern in ipairs(window_rules.ignore_classes) do
        if class:find(pattern) then return true end
    end
    for _, pattern in ipairs(window_rules.float) do
        if title:find(pattern) then return true end
    end
    return false
end

local function find_node(node, hwnd)
    if not node then return nil end
    if node.type == "leaf" and node.hwnd == hwnd then return node end
    if node.type == "split" then
        local found = find_node(node.children[1], hwnd)
        if found then return found end
        return find_node(node.children[2], hwnd)
    end
    return nil
end

local function bsp_insert(ws_id, hwnd, focused_hwnd)
    local root = HyprWin.workspace_roots[ws_id]
    local new_leaf = { type = "leaf", hwnd = hwnd, parent = nil }

    if not root then
        HyprWin.workspace_roots[ws_id] = new_leaf
        return
    end

    local target = focused_hwnd and find_node(root, focused_hwnd) or nil
    if not target then
        target = root
        while target.type == "split" do
            target = target.children[1]
        end
    end

    local parent = target.parent
    local split_node = {
        type = "split",
        direction = "h",
        ratio = 0.5,
        parent = parent,
        children = {}
    }

    local rect = HyprWin.window_rects[target.hwnd]
    if not rect then
        -- Safe system fallback during initialization
        local x, y, w, h = wm.get_window_rect(target.hwnd)
        rect = { x, y, w, h }
    end

    if rect then
        split_node.direction = (rect[3] > rect[4]) and "h" or "v"
    end

    if not parent then
        HyprWin.workspace_roots[ws_id] = split_node
    else
        if parent.children[1] == target then
            parent.children[1] = split_node
        else
            parent.children[2] = split_node
        end
    end

    target.parent = split_node
    new_leaf.parent = split_node
    split_node.children[1] = target
    split_node.children[2] = new_leaf
end

local function bsp_remove(ws_id, hwnd)
    local root = HyprWin.workspace_roots[ws_id]
    if not root then return end

    local target = find_node(root, hwnd)
    if not target then return end

    local parent = target.parent
    if not parent then
        HyprWin.workspace_roots[ws_id] = nil
        return
    end

    local sibling = (parent.children[1] == target) and parent.children[2] or parent.children[1]
    local grandparent = parent.parent

    sibling.parent = grandparent

    if not grandparent then
        HyprWin.workspace_roots[ws_id] = sibling
    else
        if grandparent.children[1] == parent then
            grandparent.children[1] = sibling
        else
            grandparent.children[2] = sibling
        end
    end
end

local function bsp_adjust_ratio(hwnd, delta)
    local ws_id = HyprWin.current_workspace
    local root = HyprWin.workspace_roots[ws_id]
    if not root then return end

    local node = find_node(root, hwnd)
    if node and node.parent then
        local parent = node.parent
        parent.ratio = math.max(0.15, math.min(0.85, parent.ratio + delta))
        HyprWin.retile()
    end
end

HyprWin.retile = function()
    -- Guard against recursive re-entrancy layout updates to prevent thread stack overflow
    if is_retiling then return end
    is_retiling = true

    -- Execute the entire layout math inside a protected call block
    local success, err = pcall(function()
        -- Deep clean the list before every math operation (Keep minimized windows!)
        local valid_windows = {}
        for _, hwnd in ipairs(HyprWin.windows) do
            -- Do NOT check for minimizing here so they stay in our tracking list
            if wm.is_window_visible(hwnd) and not wm.is_topmost(hwnd) then
                table.insert(valid_windows, hwnd)
            end
        end
        HyprWin.windows = valid_windows

        -- Ensure every window is assigned to a workspace safely
        for _, hwnd in ipairs(HyprWin.windows) do
            if not HyprWin.window_workspaces[hwnd] then
                HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            end
        end

        -- Initialize workspace ratio if not set (default 0.5)
        if not HyprWin.workspace_ratios[HyprWin.current_workspace] then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = 0.5
        end

        -- Filter active workspace, floating, and sticky windows
        local active_workspace_windows = {}
        local fullscreen_hwnd = nil

        for _, hwnd in ipairs(HyprWin.windows) do
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            local is_sticky = HyprWin.sticky_windows[hwnd]
            local is_active_ws = (ws == HyprWin.current_workspace)

            if is_active_ws or is_sticky then
                -- Uncloak active window immediately
                wm.set_cloaked(hwnd, false)

                if not wm.is_minimized(hwnd) then
                    if HyprWin.fullscreen_windows[hwnd] then
                        fullscreen_hwnd = hwnd
                    end

                    if not HyprWin.floating_windows[hwnd] then
                        table.insert(active_workspace_windows, hwnd)
                    end
                end
            else
                -- Cloak window to hide it natively
                wm.set_cloaked(hwnd, true)
            end
        end

        local sw, sh = wm.get_screen_size()
        local gap = 15
        local bar_h = 35
        
        local tx, ty = gap, bar_h + gap
        local tw, th = sw - (gap * 2), sh - bar_h - (gap * 2)

        -- Handle Monocle Fullscreen (respecting topbar)
        if fullscreen_hwnd then
            wm.move_window(fullscreen_hwnd, tx, ty, tw, th)
            HyprWin.window_rects[fullscreen_hwnd] = { tx, ty, tw, th }
            return
        end

        -- Layout recursive BSP tree
        local function layout_node(node, x, y, w, h)
            if not node then return end
            if node.type == "leaf" then
                wm.move_window(node.hwnd, x, y, w, h)
                HyprWin.window_rects[node.hwnd] = { x, y, w, h } -- Update cache
                return
            end

            if node.direction == "h" then
                local w1 = math.floor((w - gap) * node.ratio)
                layout_node(node.children[1], x, y, w1, h)
                layout_node(node.children[2], x + w1 + gap, y, w - w1 - gap, h)
            else
                local h1 = math.floor((h - gap) * node.ratio)
                layout_node(node.children[1], x, y, w, h1)
                layout_node(node.children[2], x, y + h1 + gap, w, h - h1 - gap)
            end
        end

        local root = HyprWin.workspace_roots[HyprWin.current_workspace]
        layout_node(root, tx, ty, tw, th)

        if HyprWin.layout_mode == "bsp" then
            local root = HyprWin.workspace_roots[HyprWin.current_workspace]
            layout_node(root, tx, ty, tw, th)
        elseif HyprWin.layout_mode == "master" then
            get_master_tiles(tx, ty, tw, th, active_workspace_windows)
        end
    end) -- End

    -- Unlock retiling state and report any internal math errors safely
    is_retiling = false
    if not success then
        log("RETILING ERROR: " .. tostring(err))
    end
end

HyprWin.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    -- 0x0003: Focus changed
    if event_type == 0x0003 then
        HyprWin.focused_window = hwnd
        HyprWin.focused_window_title = title -- Update cache
        if not is_tracked(hwnd) and is_valid(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            HyprWin.retile()
        end
        return
    end

    -- 0x800C: Name change
    if event_type == 0x800C and hwnd == HyprWin.focused_window then
        HyprWin.focused_window_title = title -- Update cache
        return
    end
    

     -- 0x8002: Show, 0x0017: Restore
    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            local ws = HyprWin.current_workspace
            HyprWin.window_workspaces[hwnd] = ws
            bsp_insert(ws, hwnd, HyprWin.focused_window)
        end
        HyprWin.retile()
    end

    -- 0x8001: Destroy, 0x8003: Hide
    if event_type == 0x8001 or event_type == 0x8003 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            bsp_remove(ws, hwnd)
            if HyprWin.focused_window == hwnd then
                HyprWin.focused_window = nil
            end
            HyprWin.retile()
        end
    end

    -- 0x0016: Minimize (Just trigger layout update, do NOT remove from tracking)
    if event_type == 0x0016 then
        HyprWin.retile()
    end
end

-- Global animation state for UI elements
HyprWin.ui_anims = {
    bar_y = -40,
    launcher_alpha = 0,
    alttab_scale = 0.8
}

local function lerp(current, target, speed)
    return current + (target - current) * speed
end

-- Enhanced layout logic with Master-Stack support
-- (master mode is handled inside retile via layout_mode flag)
local function get_master_tiles(tx, ty, tw, th, windows)
    local n = #windows
    if n == 1 then
        wm.move_window(windows[1], tx, ty, tw, th)
        return
    end
    local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
    local m_w   = math.floor(tw * ratio)
    wm.move_window(windows[1], tx, ty, m_w - 10, th)
    local s_h = math.floor((th - (10 * (n - 2))) / (n - 1))
    for i = 2, n do
        wm.move_window(windows[i], tx + m_w, ty + (i - 2) * (s_h + 10), tw - m_w, s_h)
    end
end

HyprWin.on_render = function()
    local time = os.clock()
    
    -- Smooth UI animations
    HyprWin.ui_anims.bar_y = lerp(HyprWin.ui_anims.bar_y, 0, HyprWin.anim_speed)
    HyprWin.ui_anims.launcher_alpha = lerp(HyprWin.ui_anims.launcher_alpha, HyprWin.launcher_active and 1 or 0, HyprWin.anim_speed)

    -- Window Borders with Neon "Flow" effect
    for _, hwnd in ipairs(HyprWin.windows) do
        local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
        if ws == HyprWin.current_workspace and not wm.is_minimized(hwnd) then
            local rect = HyprWin.window_rects[hwnd]
            if rect and hwnd == HyprWin.focused_window then
                local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
                local glow = 0.1 * math.sin(time * 5)
                ui.draw_rounded_rect(x-3, y-3, w+6, h+6, 12, 0.5, 0.3, 1.0, 0.2 + glow, 8)
                ui.draw_rounded_rect(x, y, w, h, 8, 0.6, 0.4, 1.0, 1.0, 2.5)
            end
        end
    end

    topbar.draw(HyprWin.ui_anims.bar_y)
    alttab.draw()
    launcher.draw(HyprWin.ui_anims.launcher_alpha)
end

-- Initial scan with strict workspace binding
local existing = wm.enumerate_windows()
local filtered = {}
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        table.insert(filtered, hwnd)
        HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
        bsp_insert(HyprWin.current_workspace, hwnd, nil)
    end
end

-- Returns the nearest tiled window in the given direction relative to focused
local function find_neighbor(dir)
    local focused = HyprWin.focused_window
    if not focused then return nil end

    local f_rect = HyprWin.window_rects[focused] or { wm.get_window_rect(focused) }
    local fx, fy, fw, fh = f_rect[1], f_rect[2], f_rect[3], f_rect[4]
    local fcx = fx + fw / 2
    local fcy = fy + fh / 2

    local best_hwnd = nil
    local best_dist = math.huge

    for _, hwnd in ipairs(HyprWin.windows) do
        if hwnd ~= focused and not HyprWin.floating_windows[hwnd] then
            local ws = HyprWin.window_workspaces[hwnd] or HyprWin.current_workspace
            if ws == HyprWin.current_workspace then
                local rect = HyprWin.window_rects[hwnd] or { wm.get_window_rect(hwnd) }
                local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
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

local function focus_direction(dir)
    local target = find_neighbor(dir)
    if target then wm.focus_window(target) end
end

local function swap_direction(dir)
    local focused = HyprWin.focused_window
    local target  = find_neighbor(dir)
    if not focused or not target then return end

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

HyprWin.on_hotkey = function(id)
    if id >= 101 and id <= 109 then
        -- Switch Workspace (Alt + 1..9)
        local target_ws = id - 100
        if target_ws ~= HyprWin.current_workspace then
            HyprWin.current_workspace = target_ws
            log("Switched to Workspace " .. target_ws)
            HyprWin.retile()
        end
    elseif id >= 201 and id <= 209 then
        -- Move Window to Workspace (Alt + Shift + 1..9)
        local target_ws = id - 200
        local focused = HyprWin.focused_window
        if focused then
            HyprWin.window_workspaces[focused] = target_ws
            log("Moved window " .. focused .. " to Workspace " .. target_ws)
            HyprWin.retile()
        end
    elseif id == 301 then
        -- Toggle Floating State (Alt + F)
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.floating_windows[focused] then
                HyprWin.floating_windows[focused] = nil
                HyprWin.sticky_windows[focused] = nil -- Unfloated windows cannot be sticky
                log("Window " .. focused .. " is now Tiled")
            else
                HyprWin.floating_windows[focused] = true
                log("Window " .. focused .. " is now Floating")
            end
            HyprWin.retile()
        end
    elseif id == 302 then
        -- Toggle Sticky State (Alt + P)
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.sticky_windows[focused] then
                HyprWin.sticky_windows[focused] = nil
                log("Window " .. focused .. " is no longer Sticky")
            else
                HyprWin.sticky_windows[focused] = true
                HyprWin.floating_windows[focused] = true -- Pinning requires floating state
                log("Window " .. focused .. " is now Sticky (Pinned to all workspaces)")
            end
            HyprWin.retile()
        end
    elseif id == 303 then
        -- Force Tile (Alt + T)
        local active_hwnd = wm.get_foreground_window()
        if active_hwnd and active_hwnd ~= 0 then
            wm.force_enable_resize(active_hwnd)
            if not is_tracked(active_hwnd) then
                table.insert(HyprWin.windows, active_hwnd)
                HyprWin.window_workspaces[active_hwnd] = HyprWin.current_workspace
            end
            HyprWin.floating_windows[active_hwnd] = nil
            log("Force tiled window: " .. active_hwnd)
            HyprWin.retile()
        end
    elseif id == 304 then
        -- Fullscreen Toggle with Topbar (Alt + M)
        local focused = HyprWin.focused_window
        if focused then
            if HyprWin.fullscreen_windows[focused] then
                HyprWin.fullscreen_windows[focused] = nil
                log("Fullscreen disabled for window " .. focused)
            else
                HyprWin.fullscreen_windows[focused] = true
                log("Fullscreen enabled for window " .. focused)
            end
            HyprWin.retile()
        end
    elseif id == 305 then
        -- Toggle Application Launcher (Alt + D)
        launcher.toggle()
    elseif id == 306 then
        -- Launch selected App (Alt + Enter)
        launcher.commit()
    elseif id == 401 then
        focus_direction("left") -- H
    elseif id == 402 then
        if HyprWin.launcher_active then
            launcher.navigate("down")
        else
            focus_direction("down") -- J
        end
    elseif id == 403 then
        if HyprWin.launcher_active then
            launcher.navigate("up")
        else
            focus_direction("up")   -- K
        end
    elseif id == 404 then
        focus_direction("right") -- L
    elseif id == 501 then
        swap_direction("left")
    elseif id == 502 then
        swap_direction("down")
    elseif id == 503 then
        swap_direction("up")
    elseif id == 504 then
        swap_direction("right")
    elseif id == 601 or id == 603 then
        -- Smart Resize Shrink (Ctrl + Alt + H/J)
        if HyprWin.focused_window then
            bsp_adjust_ratio(HyprWin.focused_window, -0.05)
        end
    elseif id == 602 or id == 604 then
        -- Smart Resize Grow (Ctrl + Alt + L/K)
        if HyprWin.focused_window then
            bsp_adjust_ratio(HyprWin.focused_window, 0.05)
        end
    end
end

HyprWin.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

HyprWin.windows = filtered
HyprWin.retile()