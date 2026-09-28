# HyprWin

A tiled window manager for Windows inspired by Hyprland, utilizing a dual-window C++ core with Direct2D rendering and a modular Lua configuration system.

## Technical Architecture

### 1. Rendering & Click-Through (Dual HWND Pipeline)
To bypass Windows Desktop Window Manager (DWM) pointer input limitations while maintaining a smooth desktop overlay, the application runs two separate top-level windows:
* **Overlay Window (`g_overlay_hwnd`)**: Fullscreen, non-interactive, and marked as `WS_EX_TRANSPARENT`. This window handles drawing active/inactive window borders and the application launcher. Clicks pass natively to background applications.
* **Topbar Window (`g_topbar_hwnd`)**: A topmost layered window restricted to the top of the viewport. Rather than using permanent click-through flags, it utilizes dynamic GDI regions (`SetWindowRgn`). The window boundaries are programmatically reshaped in real-time. When the settings menu is toggled, the boundary extends to capture input; when closed, it collapses back to a thin horizontal strip. Areas with an alpha of zero outside these regions allow input to reach underlying processes across separate threads.

### 2. Event Hooks & Layout Tracking
* **WinEvents**: Employs out-of-context event hooks (`SetWinEventHook`) to monitor global window state changes:
  * `EVENT_SYSTEM_FOREGROUND`: Tracks active window focus changes.
  * `EVENT_OBJECT_CREATE` / `EVENT_OBJECT_DESTROY`: Detects application window lifecycles.
  * `EVENT_SYSTEM_MINIMIZESTART` / `EVENT_SYSTEM_MINIMIZEEND`: Evaluates window state adjustments to exclude minimized targets from tiling calculations.
* **Low-Level Keyboard Hook**: Implements a dedicated keyboard hook (`WH_KEYBOARD_LL`) to intercept `Alt+Tab` key combos. Default Windows task-switching dialogs are blocked, and control is routed directly to a custom, real-time scaled window switcher handled in Lua.

### 3. Named Pipe IPC Server
The C++ core spawns a detached secondary thread hosting a multithreaded Named Pipe server listening on `\\.\pipe\hyprwin`. 
* Communication is handled via `ReadFile` and `WriteFile`.
* Commands (such as layout modifications, focus switches, and window lists) are passed down via custom `WM_HYPRWIN_IPC` window messages to the main thread's message queue, keeping thread-safety intact during Lua state execution.

### 4. Lua Execution Layer
The C++ application registers Win32 APIs, GDI functions, and Direct2D/DirectWrite rendering wrappers into the Lua state via `sol2`. Window movement, workspaces transitions (quadratic ease-out animations), and layout algorithms (such as Binary Space Partitioning and Master-stack) are computed directly in Lua on every frame delta.

---

## Build Instructions

### Prerequisites
* Windows 10/11 SDK (10.0.19041.0 or higher)
* MSVC Compiler Toolset (Visual Studio 2022 recommended)
* CMake (Version 3.20 or higher)
* Lua 5.4 Development Libraries

### Building the Project
Clone the repository and run the following commands in your terminal:

```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

The output executable and asset structure will be compiled inside the `build/Release` folder.

---

## Configuration

On initial execution, a directory is created at `%USERPROFILE%/.hyprwin/`. Edit `%USERPROFILE%/.hyprwin/hyprland.lua` to configure variables, monitors, workspace rules, custom key combinations, and animations.

```lua
-- Sample configuration block in %USERPROFILE%/.hyprwin/hyprland.lua
hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 12,
    col = {
      active_border = "rgba(bb9af7ff)",
      inactive_border = "rgba(1a1b26ff)"
    },
    layout = "bsp"
  }
})
```

---

## IPC Protocol

You can interact with `HyprWin` externally by writing raw string data to the pipe endpoint: `\\.\pipe\hyprwin`.

### Supported Commands
* `dispatch <dispatcher> <args>`: Executes layout controls (e.g., `dispatch workspace 2`, `dispatch togglefloating`, `dispatch killactive`).
* `activewindow`: Returns the focused window handle, class name, and title.
* `clients`: Outputs a list of all tracked, tiled, and floating window handles on the current layout.

---

## License

This project is licensed under the terms of the GNU General Public License v2 (GPLv2). See the `LICENSE` file for details.