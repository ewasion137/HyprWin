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
HyprWin.anim_speed = 0.15
local is_retiling = false

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function load_config()
    local path = wm.get_config_path()
    local file = io.open(path, "r")
    if not file then return end

    local settings = {}
    for line in file:lines() do
        -- Ignore comments and empty lines
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key, value = line:match("([^=]+)=([^=]+)")
            if key and value then
                settings[key:trim()] = value:trim()
            end
        end
    end
    file:close()
    return settings
end

local cfg = load_config() or {}
HyprWin.gaps_out = tonumber(cfg.gaps_out) or 15
HyprWin.layout_mode = cfg.layout_mode or "bsp"
HyprWin.anim_speed = tonumber(cfg.animation_speed) or 0.15

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
                -- Only tile if the window is NOT minimized
                if not wm.is_minimized(hwnd) then
                    -- Identify if any active window on this workspace is set to fullscreen (respecting topbar)
                    if HyprWin.fullscreen_windows[hwnd] then
                        fullscreen_hwnd = hwnd
                    end

                    if not HyprWin.floating_windows[hwnd] then
                        table.insert(active_workspace_windows, hwnd)
                    else
                        -- Restore floating or sticky window safely
                        local x, y, _, _ = wm.get_window_rect(hwnd)
                        if x < -10000 or y < -10000 then
                            local saved_rect = HyprWin.floating_rects[hwnd]
                            if saved_rect then
                                wm.move_window(hwnd, saved_rect[1], saved_rect[2], saved_rect[3], saved_rect[4])
                            else
                                -- Fallback center position
                                wm.move_window(hwnd, 150, 150, 1280, 720)
                            end
                        end
                    end
                end
            else
                -- Save floating window layout before stashing it off-screen
                if HyprWin.floating_windows[hwnd] then
                    local x, y, w, h = wm.get_window_rect(hwnd)
                    if x >= -10000 and y >= -10000 then
                        HyprWin.floating_rects[hwnd] = { x, y, w, h }
                    end
                end
                -- Move off-screen to hide from view without minimizing
                wm.move_window(hwnd, -32000, -32000, 800, 600)
            end
        end

        local sw, sh = wm.get_screen_size()
        local gap = 15
        local bar_h = 35
        
        -- Correct work area
        local tx, ty = gap, bar_h + gap
        local tw, th = sw - (gap * 2), sh - bar_h - (gap * 2)

        -- Handle Monocle Fullscreen (respecting topbar)
        if fullscreen_hwnd then
            for _, hwnd in ipairs(active_workspace_windows) do
                if hwnd == fullscreen_hwnd then
                    wm.move_window(hwnd, tx, ty, tw, th)
                else
                    wm.move_window(hwnd, -32000, -32000, 800, 600)
                end
            end
            return
        end

        local n = #active_workspace_windows
        if n == 0 then return end

        local current_ratio = HyprWin.workspace_ratios[HyprWin.current_workspace]

        -- Recursive BSP splitting with depth tracking
        local function recursive_tile(x, y, w, h, first, last, depth)
            depth = depth or 0
            if first == last then
                wm.move_window(active_workspace_windows[first], x, y, w, h)
                return
            end

            local mid = math.floor((first + last) / 2)

            -- Apply adjustable ratio only to the main split (depth 0), others are balanced
            local ratio = (depth == 0) and current_ratio or 0.5

            -- Choose split axis based on aspect ratio
            if w > h then
                -- Split vertically (left and right)
                local w1 = math.floor((w - gap) * ratio)
                recursive_tile(x, y, w1, h, first, mid, depth + 1)
                recursive_tile(x + w1 + gap, y, w - w1 - gap, h, mid + 1, last, depth + 1)
            else
                -- Split horizontally (top and bottom)
                local h1 = math.floor((h - gap) * ratio)
                recursive_tile(x, y, w, h1, first, mid, depth + 1)
                recursive_tile(x, y + h1 + gap, w, h - h1 - gap, mid + 1, last, depth + 1)
            end
        end

        recursive_tile(tx, ty, tw, th, 1, n, 0)
    end)

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
        -- Catch window on focus if we missed its show event
        if not is_tracked(hwnd) and is_valid(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
            HyprWin.retile()
        end
        return
    end

    -- 0x8002: Show, 0x0017: Restore
    if event_type == 0x8002 or event_type == 0x0017 then
        if not is_tracked(hwnd) then
            table.insert(HyprWin.windows, hwnd)
            HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace
        end
        HyprWin.retile()
    end

    -- 0x8001: Destroy, 0x8003: Hide
    if event_type == 0x8001 or event_type == 0x8003 then
        local idx = is_tracked(hwnd)
        if idx then
            table.remove(HyprWin.windows, idx)
            log("Untracked window: " .. hwnd .. " | Remaining: " .. #HyprWin.windows)
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
            local x, y, w, h = wm.get_window_rect(hwnd)
            if hwnd == HyprWin.focused_window then
                -- Multi-layered neon glow
                local glow = 0.1 * math.sin(time * 5)
                ui.draw_rounded_rect(x-3, y-3, w+6, h+6, 12, 0.5, 0.3, 1.0, 0.2 + glow, 8) -- Outer glow
                ui.draw_rounded_rect(x, y, w, h, 8, 0.6, 0.4, 1.0, 1.0, 2.5) -- Sharp border
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
        HyprWin.window_workspaces[hwnd] = HyprWin.current_workspace -- Safe initialization
    end
end

-- Returns the nearest tiled window in the given direction relative to focused
local function find_neighbor(dir)
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
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio > 0.15 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio - 0.05
            HyprWin.retile()
        end
    elseif id == 602 or id == 604 then
        -- Smart Resize Grow (Ctrl + Alt + L/K)
        local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
        if ratio < 0.85 then
            HyprWin.workspace_ratios[HyprWin.current_workspace] = ratio + 0.05
            HyprWin.retile()
        end
    end
end

HyprWin.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

HyprWin.windows = filtered
HyprWin.retile()