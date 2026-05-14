#ifndef NOMINMAX
#define NOMINMAX
#endif

#define SOL_ALL_SAFETIES_ON 1

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

// Callback function that handles Windows events
void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd,
                           LONG idObject, LONG idChild, DWORD dwEventThread,
                           DWORD dwmsEventTime) {
  // We only care about main window objects
  if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == NULL)
    return;

  if (!IsWindowVisible(hwnd) || !IsToplevelWindow(hwnd))
    return;

  // Call Lua dispatcher
  if (g_lua) {
    char title[256];
    GetWindowTextA(hwnd, title, sizeof(title));

    // Use a safe call to the Lua dispatcher
    sol::protected_function dispatcher = (*g_lua)["HyprWin"]["dispatch_event"];
    if (dispatcher.valid()) {
      dispatcher(event, (size_t)hwnd, std::string(title));
    }
  }
}

bool IsToplevelWindow(HWND hwnd) {
  long style = GetWindowLong(hwnd, GWL_STYLE);
  long ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
  HWND owner = GetWindowIdentify(hwnd); // Check if window has an owner

  // Filter out tooltips, child windows, and popups without a taskbar icon
  if (ex_style & WS_EX_TOOLWINDOW)
    return false;
  if (owner != NULL)
    return false; // Real app windows usually don't have an owner
  if (!(style & WS_CAPTION))
    return false;

  // Ignore small "ghost" windows
  RECT rect;
  GetWindowRect(hwnd, &rect);
  if ((rect.right - rect.left) <= 1 || (rect.bottom - rect.top) <= 1)
    return false;

  return true;
}

int main() {
  // Wrap everything in a try-catch to catch sol2 exceptions
  try {
    std::cout << "HyprWin: Initializing Lua engine..." << std::endl;
    sol::state lua;
    g_lua = &lua;

    // Open standard libraries safely
    lua.open_libraries(sol::lib::base, sol::lib::package);

    // Bind a C++ function to Lua
    lua.set_function("log", [](std::string message) {
      std::cout << "[LUA]: " << message << std::endl;
    });
    auto wm = lua.create_named_table("wm");

    wm.set_function("get_class_name", [](size_t hwnd) {
      char class_name[256];
      GetClassNameA((HWND)hwnd, class_name, sizeof(class_name));
      return std::string(class_name);
    });
    
    wm.set_function("move_window", [](size_t hwnd, int x, int y, int w, int h) {
      SetWindowPos((HWND)hwnd, NULL, x, y, w, h,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    });

    wm.set_function("get_screen_size", []() {
      return std::make_pair(GetSystemMetrics(SM_CXSCREEN),
                            GetSystemMetrics(SM_CYSCREEN));
    });

    char buffer[MAX_PATH];
    GetModuleFileNameA(NULL, buffer, MAX_PATH);
    std::string path(buffer);
    std::string exe_dir = path.substr(0, path.find_last_of("\\/"));

    // Load the entry point script from the scripts folder
    std::string script_path = exe_dir + "\\scripts\\main.lua";

    std::cout << "HyprWin: Loading script from " << script_path << std::endl;

    auto result = lua.script_file(script_path);
    HWINEVENTHOOK hook =
        SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_HIDE, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    if (!hook) {
      std::cerr << "HyprWin: Failed to register WinEventHook!" << std::endl;
      return 1;
    }

    std::cout << "HyprWin: Window hook registered. Monitoring windows..."
              << std::endl;

    // Message loop is REQUIRED for hooks to work
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }

    UnhookWinEvent(hook);
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