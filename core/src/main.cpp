#ifndef NOMINMAX
#define NOMINMAX
#endif

#define SOL_ALL_SAFETIES_ON 1

#include "../include/renderer.hpp"
#include "../include/alttab.hpp"
#include <dwmapi.h>
#include <shellapi.h>
#include <iostream>
#include <string>
#include <windows.h>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include <sol/sol.hpp> // Move this ABOVE the global pointer and callback

// Now types are known to the compiler
sol::state *g_lua = nullptr;
Renderer g_renderer;
HWND g_overlay_hwnd = NULL;

static FILETIME g_prev_idle_time = {0};
static FILETIME g_prev_kernel_time = {0};
static FILETIME g_prev_user_time = {0};

double GetCPUUsage() {
  FILETIME idleTime, kernelTime, userTime;
  if (GetSystemTimes(&idleTime, &kernelTime, &userTime)) {
    ULARGE_INTEGER idle, kernel, user;
    idle.LowPart = idleTime.dwLowDateTime; idle.HighPart = idleTime.dwHighDateTime;
    kernel.LowPart = kernelTime.dwLowDateTime; kernel.HighPart = kernelTime.dwHighDateTime;
    user.LowPart = userTime.dwLowDateTime; user.HighPart = userTime.dwHighDateTime;

    ULARGE_INTEGER prev_idle, prev_kernel, prev_user;
    prev_idle.LowPart = g_prev_idle_time.dwLowDateTime; prev_idle.HighPart = g_prev_idle_time.dwHighDateTime;
    prev_kernel.LowPart = g_prev_kernel_time.dwLowDateTime; prev_kernel.HighPart = g_prev_kernel_time.dwHighDateTime;
    prev_user.LowPart = g_prev_user_time.dwLowDateTime; prev_user.HighPart = g_prev_user_time.dwHighDateTime;

    ULONGLONG idle_diff = idle.QuadPart - prev_idle.QuadPart;
    ULONGLONG kernel_diff = kernel.QuadPart - prev_kernel.QuadPart;
    ULONGLONG user_diff = user.QuadPart - prev_user.QuadPart;

    g_prev_idle_time = idleTime;
    g_prev_kernel_time = kernelTime;
    g_prev_user_time = userTime;

    ULONGLONG total = kernel_diff + user_diff;
    if (total == 0) return 0.0;
    return (double)(total - idle_diff) * 100.0 / total;
  }
  return 0.0;
}

bool IsToplevelWindow(HWND hwnd) {
  DWORD pid;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == GetCurrentProcessId())
    return false;

  long style = GetWindowLong(hwnd, GWL_STYLE);
  long ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
  HWND owner = GetWindow(hwnd, GW_OWNER);

  // --- FIXED LOGIC START ---
  // 1. If window is TOPMOST (PiP, Overlays) - IGNORE IT
  if (ex_style & WS_EX_TOPMOST)
    return false;

  // 2. Standard Top-Level requirements
  bool isAppWindow = (ex_style & WS_EX_APPWINDOW);
  bool isTopLevel = (style & WS_CAPTION) && (owner == NULL);

  if (ex_style & WS_EX_TOOLWINDOW)
    return false;
  if (!isAppWindow && !isTopLevel)
    return false;
  // --- FIXED LOGIC END ---

  int cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                      sizeof(cloaked))) &&
      cloaked != 0) {
    return false;
  }

  return true;
}

void RestoreAllWindows() {
  EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
    BOOL fCloak = FALSE;
    DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, &fCloak, sizeof(fCloak));
    return TRUE;
  }, 0);
}

BOOL WINAPI ConsoleHandler(DWORD ctrlType) {
  if (ctrlType == CTRL_CLOSE_EVENT || ctrlType == CTRL_C_EVENT || 
      ctrlType == CTRL_LOGOFF_EVENT || ctrlType == CTRL_SHUTDOWN_EVENT) {
    RestoreAllWindows();
    return TRUE;
  }
  return FALSE;
}

// Callback function that handles Windows events
void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                           LONG idObject, LONG idChild, DWORD dwEventThread,
                           DWORD dwmsEventTime) {
  // We only care about main window objects
  if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == NULL)
    return;

  if (event == 0x800B || event == 0x800A)
    return;
  // Bypass visibility/toplevel checks for destroy, hide, and minimize events
  // since the window is no longer fully valid/visible at this stage, but we
  // still need to untrack it.
  bool is_destroy_or_hide =
      (event == EVENT_OBJECT_DESTROY || event == EVENT_OBJECT_HIDE ||
       event == EVENT_SYSTEM_MINIMIZESTART);

  if (!is_destroy_or_hide) {
    if (!IsWindowVisible(hwnd) || !IsToplevelWindow(hwnd))
      return;
  }

  // Call Lua dispatcher
  if (g_lua) {
    char title[256];
    GetWindowTextA(hwnd, title, sizeof(title));

    // Log the caught event to console for debugging
    std::cout << "[Hook Event] HWND: 0x" << std::hex << (size_t)hwnd << std::dec
              << " | Event: 0x" << std::hex << event << std::dec
              << " | Title: " << title << std::endl;

    sol::protected_function dispatcher = (*g_lua)["HyprWin"]["dispatch_event"];
    if (dispatcher.valid()) {
      auto result = dispatcher(event, (size_t)hwnd, std::string(title));
      if (event == EVENT_SYSTEM_FOREGROUND) {
        sol::protected_function retile = (*g_lua)["HyprWin"]["retile"];
        if (retile.valid())
          retile();
      }
      if (!result.valid()) {
        sol::error err = result;
        std::cerr << "!!! LUA EVENT ERROR: " << err.what() << std::endl;
      }
    } else {
      std::cerr << "!!! LUA WARNING: HyprWin.dispatch_event is not defined!"
                << std::endl;
    }
  }
}

int main() {
  // Wrap everything in a try-catch to catch sol2 exceptions
  try {
    SetConsoleCtrlHandler(ConsoleHandler, TRUE);
    std::cout << "HyprWin: Initializing Lua engine..." << std::endl;
    sol::state lua;
    g_lua = &lua;

    // Open standard libraries safely (including OS library for clocks/timers)
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string,
                       sol::lib::math, sol::lib::table, sol::lib::os);

    // Bind a C++ function to Lua
    lua.set_function("log", [](std::string message) {
      std::cout << "[LUA]: " << message << std::endl;
    });
    auto wm = lua.create_named_table("wm");

    wm.set_function("get_class_name", [](size_t hwnd) {
      char class_name[256] = {0};
      GetClassNameA((HWND)hwnd, class_name, sizeof(class_name));
      return std::string(class_name);
    });

    wm.set_function("get_window_title", [](size_t hwnd) {
      char title[256] = {0};
      GetWindowTextA((HWND)hwnd, title, sizeof(title));
      return std::string(title);
    });

    wm.set_function("is_topmost", [](size_t hwnd) {
      LONG ex_style = GetWindowLong((HWND)hwnd, GWL_EXSTYLE);
      return (bool)(ex_style & WS_EX_TOPMOST);
    });

    wm.set_function("get_foreground_window", []() {
      return (size_t)GetForegroundWindow();
    });

    wm.set_function("get_cpu_usage", []() {
      return GetCPUUsage();
    });

    wm.set_function("get_ram_usage", []() {
      MEMORYSTATUSEX memInfo;
      memInfo.dwLength = sizeof(MEMORYSTATUSEX);
      GlobalMemoryStatusEx(&memInfo);
      return (double)memInfo.dwMemoryLoad;
    });

    wm.set_function("spawn", [](std::string command) {
      ShellExecuteA(NULL, "open", command.c_str(), NULL, NULL, SW_SHOWNORMAL);
    });

    wm.set_function("focus_window", [](size_t hwnd) {
      HWND handle = (HWND)hwnd;
      
      // Auto-restore window if it was minimized
      if (IsIconic(handle)) {
        ShowWindow(handle, SW_RESTORE);
      } else {
        ShowWindow(handle, SW_SHOW);
      }

      // 1. Temporarily disable the global foreground lock timeout
      SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, (LPVOID)0, SPIF_SENDCHANGE);

      // 2. Simulate a rapid ALT key tap to bypass Windows focus stealing protection
      keybd_event(VK_MENU, 0, 0, 0);
      keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);

      // 3. Thread attachment fallback to ensure keyboard input follows the window
      HWND fg = GetForegroundWindow();
      DWORD fgThread = GetWindowThreadProcessId(fg, NULL);
      DWORD currentThread = GetCurrentThreadId();

      if (fgThread != currentThread && fgThread != 0) {
        AttachThreadInput(currentThread, fgThread, TRUE);
        SetForegroundWindow(handle);
        BringWindowToTop(handle);
        SetActiveWindow(handle);
        SetFocus(handle);
        AttachThreadInput(currentThread, fgThread, FALSE);
      } else {
        SetForegroundWindow(handle);
        BringWindowToTop(handle);
        SetActiveWindow(handle);
        SetFocus(handle);
      }
    });

    wm.set_function("force_enable_resize", [](size_t hwnd) {
      HWND handle = (HWND)hwnd;
      long style = GetWindowLong(handle, GWL_STYLE);
      style |= (WS_THICKFRAME | WS_MAXIMIZEBOX);
      SetWindowLong(handle, GWL_STYLE, style);
      SetWindowPos(handle, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    });

    wm.set_function("move_window", [](size_t hwnd, double x, double y, double w,
                                      double h) {
      HWND handle = (HWND)hwnd;
      RECT windowRect;
      if (IsZoomed(handle)) {
        ShowWindow(handle, SW_RESTORE);
      }
      GetWindowRect(handle, &windowRect);

      RECT frameRect;
      if (SUCCEEDED(DwmGetWindowAttribute(handle, DWMWA_EXTENDED_FRAME_BOUNDS,
                                          &frameRect, sizeof(RECT)))) {
        int leftMargin = frameRect.left - windowRect.left;
        int topMargin = frameRect.top - windowRect.top;
        int rightMargin = windowRect.right - frameRect.right;
        int bottomMargin = windowRect.bottom - frameRect.bottom;

        int finalX = (int)x - leftMargin;
        int finalY = (int)y - topMargin;
        int finalW = (int)w + leftMargin + rightMargin;
        int finalH = (int)h + topMargin + bottomMargin;

        // Use SWP_NOACTIVATE and SWP_NOSENDCHANGING to optimize drawing
        SetWindowPos(handle, HWND_NOTOPMOST, finalX, finalY, finalW, finalH,
                     SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_NOSENDCHANGING);
      } else {
        // Fallback to normal SetWindowPos if DWM bounds are unavailable
        SetWindowPos(handle, HWND_NOTOPMOST, (int)x, (int)y, (int)w, (int)h,
                     SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_NOSENDCHANGING);
      }
    });
    
    wm.set_function("get_screen_size", []() {
      return std::make_pair(GetSystemMetrics(SM_CXSCREEN),
                            GetSystemMetrics(SM_CYSCREEN));
    });

    wm.set_function("get_window_rect", [](size_t hwnd) {
      RECT rect = {0};
      // Use DWM attribute to get bounds WITHOUT invisible shadows
      if (SUCCEEDED(DwmGetWindowAttribute(
              (HWND)hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rect, sizeof(RECT)))) {
        return std::make_tuple((int)rect.left, (int)rect.top,
                               (int)(rect.right - rect.left),
                               (int)(rect.bottom - rect.top));
      }
      // Fallback to normal rect if DWM fails
      GetWindowRect((HWND)hwnd, &rect);
      return std::make_tuple((int)rect.left, (int)rect.top,
                             (int)(rect.right - rect.left),
                             (int)(rect.bottom - rect.top));
    });

    wm.set_function("is_window_visible", [](size_t hwnd) {
      if (!IsWindowVisible((HWND)hwnd)) return false;
      int cloaked = 0;
      if (SUCCEEDED(DwmGetWindowAttribute((HWND)hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
        return false;
      }
      return true;
    });
    wm.set_function("set_cloaked", [](size_t hwnd, bool cloaked) {
      BOOL fCloak = cloaked ? TRUE : FALSE;
      DwmSetWindowAttribute((HWND)hwnd, DWMWA_CLOAK, &fCloak, sizeof(fCloak));
    });

    wm.set_function("is_minimized",
                    [](size_t hwnd) { return (bool)IsIconic((HWND)hwnd); });

    wm.set_function("enumerate_windows", []() {
      std::vector<size_t> hwnds;
      EnumWindows(
          [](HWND hwnd, LPARAM lParam) -> BOOL {
            auto list = (std::vector<size_t> *)lParam;
            if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
              int cloaked = 0;
              if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
                return TRUE;
              }
              list->push_back((size_t)hwnd);
            }
            return TRUE;
          },
          (LPARAM)&hwnds);
      return hwnds;
    });
    auto ui = lua.create_named_table("ui");

    ui.set_function("draw_rect",
                    [](float x, float y, float w, float h, float r, float g,
                       float b, float a, float thickness) {
                      g_renderer.draw_rect(x, y, w, h, r, g, b, a, thickness);
                    });
    ui.set_function("fill_rect", [](float x, float y, float w, float h, float r,
                                    float g, float b, float a) {
      g_renderer.fill_rect(x, y, w, h, r, g, b, a);
    });

    ui.set_function("draw_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float thick) {
        g_renderer.draw_rounded_rect(x, y, w, h, rad, r, g, b, a, thick);
    });

    ui.set_function("fill_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a) {
        g_renderer.fill_rounded_rect(x, y, w, h, rad, r, g, b, a);
    });
    ui.set_function("draw_text", [](std::string text, float x, float y, float size,
                                    float r, float g, float b, float a, std::string font) {
      g_renderer.draw_text(text, x, y, size, r, g, b, a, font);
    });

    // Returns pixel width of a string — useful for right-aligning text in Lua
    ui.set_function("measure_text", [](std::string text, float size, std::string font) {
      return g_renderer.measure_text_width(text, size, font);
    });
    ui.set_function("render", []() {
      g_renderer.begin_draw();
      g_renderer.clear(0, 0, 0, 0); // Transparent background

      // Call a Lua function to handle frame drawing with full error catching
      if (g_lua) {
        sol::protected_function draw_func = (*g_lua)["HyprWin"]["on_render"];
        if (draw_func.valid()) {
          auto result = draw_func();
          if (!result.valid()) {
            sol::error err = result;
            std::cerr << "!!! LUA RENDER ERROR: " << err.what() << std::endl;
          }
        }
      }

      g_renderer.end_draw();
    });
    WNDCLASSEXA wc = {sizeof(WNDCLASSEXA),
                      CS_HREDRAW | CS_VREDRAW,
                      DefWindowProcA,
                      0,
                      0,
                      GetModuleHandle(NULL),
                      NULL,
                      NULL,
                      (HBRUSH)GetStockObject(
                          BLACK_BRUSH), // Use BLACK_BRUSH for DWM transparency
                      NULL,
                      "HyprWinOverlay",
                      NULL};
    RegisterClassExA(&wc);

    HWND overlay_hwnd = CreateWindowExA(
        WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_LAYERED, "HyprWinOverlay",
        "Overlay", WS_POPUP, 0, 0, GetSystemMetrics(SM_CXSCREEN),
        GetSystemMetrics(SM_CYSCREEN), NULL, NULL, wc.hInstance, NULL);

    g_overlay_hwnd = overlay_hwnd; // Store globally

    // Set the window to be fully opaque layered window first
    SetLayeredWindowAttributes(overlay_hwnd, 0, 255, LWA_ALPHA);

    MARGINS margins = {-1};
    DwmExtendFrameIntoClientArea(overlay_hwnd, &margins);

    // Check if renderer initialized properly
    if (!g_renderer.init(overlay_hwnd)) {
      std::cerr << "HyprWin: Failed to initialize Renderer!" << std::endl;
      return -1;
    }

    ShowWindow(overlay_hwnd, SW_SHOW);

    // Set transparency and click-through
    SetWindowPos(overlay_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    // --- FIXED CODE END ---

    char buffer[MAX_PATH];
    GetModuleFileNameA(NULL, buffer, MAX_PATH);

    std::string path(buffer);
    std::string exe_dir = path.substr(0, path.find_last_of("\\/"));

    // Load the entry point script from the scripts folder
    std::string script_path = exe_dir + "\\scripts\\main.lua";

    std::cout << "HyprWin: Loading script from " << script_path << std::endl;

    sol::protected_function_result result = lua.script_file(script_path);
    if (!result.valid()) {
      sol::error err = result;
      std::cerr << "!!! LUA SCRIPT ERROR: Failed to load/run " << script_path
                << std::endl;
      std::cerr << "Details: " << err.what() << std::endl;
      std::cout << "Press Enter to exit..." << std::endl;
      std::cin.get();
      return 1;
    }
    std::cout << "HyprWin: Lua script loaded successfully!" << std::endl;

    // Hook for window creation, destruction, show, hide and namechange events
    // (0x8000 to 0x800C)
    HWINEVENTHOOK hook_objects =
        SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_NAMECHANGE, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    // Hook for system foreground (focus) changes
    HWINEVENTHOOK hook_focus =
        SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    // Hook for system minimize/restore events (0x0016 to 0x0017)
    HWINEVENTHOOK hook_minimize =
        SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND,
                        NULL, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    if (!hook_objects || !hook_focus || !hook_minimize) {
      std::cerr << "HyprWin: Failed to register WinEventHooks!" << std::endl;
      return 1;
    }

    // Start our custom low-level Alt+Tab hook
    if (!InitializeAltTabHook()) {
      std::cerr << "HyprWin: Failed to register low-level Keyboard hook!" << std::endl;
      return 1;
    }

    std::cout << "HyprWin: Window hook registered. Monitoring windows..."
              << std::endl;

    // Register hotkeys for Workspaces (Alt + 1..9) and moving windows (Alt + Shift + 1..9)
    for (int i = 1; i <= 9; ++i) {
      RegisterHotKey(NULL, 101 + (i - 1), MOD_ALT, '0' + i);
      RegisterHotKey(NULL, 201 + (i - 1), MOD_ALT | MOD_SHIFT, '0' + i);
    }
    // Register Alt + F to toggle Floating state, and Alt + P to Pin (Sticky)
    RegisterHotKey(NULL, 301, MOD_ALT, 'F');
    RegisterHotKey(NULL, 302, MOD_ALT, 'P');
    RegisterHotKey(NULL, 303, MOD_ALT, 'T'); // Force Tile hotkey
    RegisterHotKey(NULL, 304, MOD_ALT, 'M'); // Fullscreen with topbar (Monocle)
    RegisterHotKey(NULL, 305, MOD_ALT, 'D'); // Spawn Launcher (Rofi-like)
    RegisterHotKey(NULL, 306, MOD_ALT, VK_RETURN); // Commit Launcher selection (Alt+Enter)

    // Focus Movement (Alt + H/J/K/L to avoid conflicts with IDEs)
    RegisterHotKey(NULL, 401, MOD_ALT, 'H');
    RegisterHotKey(NULL, 402, MOD_ALT, 'J');
    RegisterHotKey(NULL, 403, MOD_ALT, 'K');
    RegisterHotKey(NULL, 404, MOD_ALT, 'L');

    // Window Swap (Alt + Shift + H/J/K/L)
    RegisterHotKey(NULL, 501, MOD_ALT | MOD_SHIFT, 'H');
    RegisterHotKey(NULL, 502, MOD_ALT | MOD_SHIFT, 'J');
    RegisterHotKey(NULL, 503, MOD_ALT | MOD_SHIFT, 'K');
    RegisterHotKey(NULL, 504, MOD_ALT | MOD_SHIFT, 'L');

    // Smart Resize Ratio (Ctrl + Alt + H/L)
    RegisterHotKey(NULL, 601, MOD_CONTROL | MOD_ALT, 'H');
    RegisterHotKey(NULL, 603, MOD_CONTROL | MOD_ALT, 'J');
    RegisterHotKey(NULL, 604, MOD_CONTROL | MOD_ALT, 'K');
    RegisterHotKey(NULL, 602, MOD_CONTROL | MOD_ALT, 'L');


    // Message loop is REQUIRED for hooks to work
    MSG msg;
    while (true) {
      // Check for messages without blocking to keep rendering smooth
      if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT)
          break;

        if (msg.message == WM_HOTKEY) {
          int hotkey_id = (int)msg.wParam;
          if (g_lua) {
            sol::protected_function on_hotkey = (*g_lua)["HyprWin"]["on_hotkey"];
            if (on_hotkey.valid()) {
              auto result = on_hotkey(hotkey_id);
              if (!result.valid()) {
                sol::error err = result;
                std::cerr << "!!! LUA HOTKEY ERROR: " << err.what() << std::endl;
              }
            }
          }
        }
        if (msg.message == WM_HYPRWIN_ALTTAB) {
          if (g_lua) {
            sol::protected_function alttab_func = (*g_lua)["HyprWin"]["on_alttab_action"];
            if (alttab_func.valid()) {
              const char* action = "next";
              if (msg.wParam == 2) action = "prev";
              else if (msg.wParam == 3) action = "commit";

              auto result = alttab_func(action);
              if (!result.valid()) {
                sol::error err = result;
                std::cerr << "!!! LUA ALTTAB ERROR: " << err.what() << std::endl;
              }
            }
          }
        }

        TranslateMessage(&msg);
        DispatchMessage(&msg);
      } else {
        // Yield CPU to prevent high core usage (caps frame rate around 60fps)
        Sleep(16);
      }

      // Check if the foreground window is in fullscreen (e.g., games)
      HWND fg = GetForegroundWindow();
      bool is_fullscreen = false;

      if (fg && fg != g_overlay_hwnd && !IsZoomed(fg)) {
        char className[256] = {0};
        GetClassNameA(fg, className, sizeof(className));
        std::string cls(className);

        // Never hide overlay if foreground is the desktop background, system tray, or explorer folders
        if (cls != "WorkerW" && cls != "Progman" && cls != "Shell_TrayWnd" && cls != "HyprWinOverlay" && cls != "CabinetWClass") {
          RECT rc;
          if (SUCCEEDED(DwmGetWindowAttribute(fg, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof(rc)))) {
            int screen_w = GetSystemMetrics(SM_CXSCREEN);
            int screen_h = GetSystemMetrics(SM_CYSCREEN);
            is_fullscreen = (rc.left <= 0 && rc.top <= 0 && rc.right >= screen_w && rc.bottom >= screen_h);
          }
        }
      }

      if (is_fullscreen) {
        if (IsWindowVisible(g_overlay_hwnd)) {
          char className[256] = {0};
          GetClassNameA(fg, className, sizeof(className));
          std::cout << "[Fullscreen Detect] Hiding overlay. Active window class: " << className << std::endl;
          ShowWindow(g_overlay_hwnd, SW_HIDE);
        }
      } else {
        if (!IsWindowVisible(g_overlay_hwnd)) {
          std::cout << "[Fullscreen Detect] Restoring overlay visibility." << std::endl;
          ShowWindow(g_overlay_hwnd, SW_SHOWNOACTIVATE);
        }
      }

      // Trigger Lua rendering only if overlay is visible to save GPU resources
      if (IsWindowVisible(g_overlay_hwnd)) {
        sol::protected_function render_func = lua["ui"]["render"];
        if (render_func.valid()) {
          render_func();
        }
      }
    }

    // Unregister all hotkeys on clean exit
    for (int i = 101; i <= 109; ++i) UnregisterHotKey(NULL, i);
    for (int i = 201; i <= 209; ++i) UnregisterHotKey(NULL, i);
    for (int i = 301; i <= 306; ++i) UnregisterHotKey(NULL, i);
    for (int i = 401; i <= 404; ++i) UnregisterHotKey(NULL, i);
    for (int i = 501; i <= 504; ++i) UnregisterHotKey(NULL, i);
    for (int i = 601; i <= 604; ++i) UnregisterHotKey(NULL, i);

    UnhookWinEvent(hook_objects);
    UnhookWinEvent(hook_focus);
    UnhookWinEvent(hook_minimize);

    CleanupAltTabHook();

    RestoreAllWindows();

  } catch (const sol::error &e) {
    std::cerr << "!!! LUA ERROR: " << e.what() << std::endl;
  } catch (const std::exception &e) {
    std::cerr << "!!! SYSTEM ERROR: " << e.what() << std::endl;
  } catch (...) {
    std::cerr << "!!! UNKNOWN CRASH !!!" << std::endl;
  }

  std::cout << "\nPress Enter to exit..." << std::endl;
  std::cin.get();

  return 0;
}