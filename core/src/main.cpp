#ifndef NOMINMAX
#define NOMINMAX
#endif

#define SOL_ALL_SAFETIES_ON 1

#include "../include/renderer.hpp"
#include <dwmapi.h>
#include <iostream>
#include <string> // Added for std::string
#include <windows.h>


// --- FIXED CODE LOCATOR: Header order ---
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include <sol/sol.hpp> // Move this ABOVE the global pointer and callback

// Now types are known to the compiler
sol::state *g_lua = nullptr;
Renderer g_renderer;

bool IsToplevelWindow(HWND hwnd) {
  // Ignore our overlay window to avoid tiling it
  char class_name[256] = {0};
  GetClassNameA(hwnd, class_name, sizeof(class_name));
  if (strcmp(class_name, "HyprWinOverlay") == 0)
    return false;

  long style = GetWindowLong(hwnd, GWL_STYLE);
  long ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
  HWND owner = GetWindow(hwnd, GW_OWNER);

  if (ex_style & WS_EX_TOOLWINDOW)
    return false;
  if (owner != NULL)
    return false;
  if (!(style & WS_CAPTION))
    return false;

  // Filter out cloaked windows (suspended UWP apps, virtual desktops, background apps)
  int cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
    return false;
  }

  RECT rect;
  GetWindowRect(hwnd, &rect);
  if ((rect.right - rect.left) <= 1 || (rect.bottom - rect.top) <= 1)
    return false;

  // Filter out windows with empty titles (helper/invisible utility windows)
  char title[256] = {0};
  GetWindowTextA(hwnd, title, sizeof(title));
  if (strlen(title) == 0)
    return false;

  return true;
}
// Callback function that handles Windows events
void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                           LONG idObject, LONG idChild, DWORD dwEventThread,
                           DWORD dwmsEventTime) {
  // We only care about main window objects
  if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == NULL)
    return;

  // Bypass visibility/toplevel checks for destroy, hide, and minimize events since the window
  // is no longer fully valid/visible at this stage, but we still need to untrack it.
  bool is_destroy_or_hide = (event == EVENT_OBJECT_DESTROY || event == EVENT_OBJECT_HIDE || event == EVENT_SYSTEM_MINIMIZESTART);
  
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
      if (!result.valid()) {
        sol::error err = result;
        std::cerr << "!!! LUA EVENT ERROR: " << err.what() << std::endl;
      }
    } else {
      std::cerr << "!!! LUA WARNING: HyprWin.dispatch_event is not defined!" << std::endl;
    }
  }
}

int main() {
  // Wrap everything in a try-catch to catch sol2 exceptions
  try {
    std::cout << "HyprWin: Initializing Lua engine..." << std::endl;
    sol::state lua;
    g_lua = &lua;

    // Open standard libraries safely
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string, sol::lib::math, sol::lib::table);

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

    wm.set_function(
        "move_window", [](size_t hwnd, double x, double y, double w, double h) {
          // Added SWP_NOZORDER to keep our overlay on top, but removed
          // SWP_NOACTIVATE if you want the tiled window to actually be usable
          SetWindowPos((HWND)hwnd, HWND_BOTTOM, (int)x, (int)y, (int)w, (int)h,
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
        });

    wm.set_function("get_screen_size", []() {
      return std::make_pair(GetSystemMetrics(SM_CXSCREEN),
                            GetSystemMetrics(SM_CYSCREEN));
    });

    wm.set_function("get_window_rect", [](size_t hwnd) {
      RECT rect = {0};
      if (GetWindowRect((HWND)hwnd, &rect)) {
        // Returns x, y, width, height (explicitly cast to int to match return types)
        return std::make_tuple((int)rect.left, (int)rect.top, (int)(rect.right - rect.left), (int)(rect.bottom - rect.top));
      }
      return std::make_tuple(0, 0, 0, 0);
    });

    wm.set_function("is_window_visible", [](size_t hwnd) {
      return (bool)IsWindowVisible((HWND)hwnd);
    });

    wm.set_function("is_minimized", [](size_t hwnd) {
      return (bool)IsIconic((HWND)hwnd);
    });

    wm.set_function("enumerate_windows", []() {
      std::vector<size_t> hwnds;
      EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
        auto list = (std::vector<size_t>*)lParam;
        if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
          list->push_back((size_t)hwnd);
        }
        return TRUE;
      }, (LPARAM)&hwnds);
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
    ui.set_function("render", []() {
      g_renderer.begin_draw();
      g_renderer.clear(0, 0, 0, 0); // Transparent background

      // Call a Lua function to handle frame drawing
      if (g_lua) {
        sol::protected_function draw_func = (*g_lua)["HyprWin"]["on_render"];
        if (draw_func.valid())
          draw_func();
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

    g_renderer.init(overlay_hwnd);

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
      std::cerr << "!!! LUA SCRIPT ERROR: Failed to load/run " << script_path << std::endl;
      std::cerr << "Details: " << err.what() << std::endl;
      std::cout << "Press Enter to exit..." << std::endl;
      std::cin.get();
      return 1;
    }
    std::cout << "HyprWin: Lua script loaded successfully!" << std::endl;
    
    // Hook for window creation, destruction, show, hide and namechange events (0x8000 to 0x800C)
    HWINEVENTHOOK hook_objects =
        SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_NAMECHANGE, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    // Hook for system foreground (focus) changes
    HWINEVENTHOOK hook_focus =
        SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    // Hook for system minimize/restore events (0x0016 to 0x0017)
    HWINEVENTHOOK hook_minimize =
        SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    if (!hook_objects || !hook_focus || !hook_minimize) {
      std::cerr << "HyprWin: Failed to register WinEventHooks!" << std::endl;
      return 1;
    }

    std::cout << "HyprWin: Window hook registered. Monitoring windows..."
              << std::endl;

    // Message loop is REQUIRED for hooks to work
    MSG msg;
    while (true) {
      // Check for messages without blocking to keep rendering smooth
      if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT)
          break;
        TranslateMessage(&msg);
        DispatchMessage(&msg);
      }

      // Trigger Lua rendering
      sol::protected_function render_func = lua["ui"]["render"];
      if (render_func.valid()) {
        render_func();
      }
    }

    UnhookWinEvent(hook_objects);
    UnhookWinEvent(hook_focus);
    UnhookWinEvent(hook_minimize);
    
    if (result.valid()) {
      std::cout << "HyprWin: Lua test passed." << std::endl;
    }

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