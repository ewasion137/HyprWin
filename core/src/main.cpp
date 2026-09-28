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
#include <filesystem>
#include <fstream>
#include <windowsx.h>
#include <shlobj.h>
#include <thread>
#include <vector>


extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include <sol/sol.hpp> // Move this ABOVE the global pointer and callback
#include <mutex> // ИСПРАВЛЕНО: добавляем мьютекс для thread-safety

// Now types are known to the compiler
sol::state *g_lua = nullptr;
std::mutex g_lua_mutex; // ИСПРАВЛЕНО: мьютекс для защиты доступа к g_lua
Renderer g_renderer;
HWND g_overlay_hwnd = NULL;
namespace fs = std::filesystem;
std::vector<int> g_registered_hotkeys;

// УДАЛЕНО: topbar renderer и hwnd больше не нужны
Renderer* g_current_renderer = nullptr; // Points to currently active renderer

#define WM_HYPRWIN_IPC (WM_USER + 500)

struct IPCMessage {
  const char* request;
  std::string response;
};

#define WM_HYPRWIN_IPC (WM_USER + 500)
#define WM_HYPRWIN_ALTTAB (WM_USER + 501)

LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_HYPRWIN_ALTTAB: {
        if (!g_lua) return 0;
        std::lock_guard<std::mutex> lock(g_lua_mutex);
        sol::protected_function fn = (*g_lua)["HyprWin"]["on_alttab_action"];
        if (fn.valid()) {
            const char* act = (wParam == 3) ? "cancel" : ((wParam == 2) ? "commit" : ((wParam == 1) ? "prev" : "next"));
            fn(act);
        }
        return 0;
    }
    case WM_HYPRWIN_IPC: {
        auto* ipcm = reinterpret_cast<IPCMessage*>(lParam);
        if (ipcm && g_lua) {
            std::lock_guard<std::mutex> lock(g_lua_mutex);
            sol::protected_function fn = (*g_lua)["HyprWin"]["on_ipc_request"];
            if (fn.valid()) {
                auto res = fn(ipcm->request);
                if (res.valid()) {
                    ipcm->response = res.get<std::string>();
                } else {
                    sol::error err = res;
                    ipcm->response = "LUA ERROR: " + std::string(err.what());
                }
            } else {
                ipcm->response = "ERROR: IPC handler missing";
            }
        }
        return 1;
    }
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
}

void IPCServerThread() {
    while (true) {
        HANDLE hPipe = CreateNamedPipeA(
            "\\\\.\\pipe\\hyprwin",
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            1,
            2048, 2048, 0, nullptr
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
            Sleep(500);
            continue;
        }

        if (ConnectNamedPipe(hPipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED)) {
            char buffer[2048];
            DWORD bytesRead = 0;
            if (ReadFile(hPipe, buffer, sizeof(buffer) - 1, &bytesRead, nullptr) && bytesRead > 0) {
                buffer[bytesRead] = '\0';
                IPCMessage msg;
                msg.request = buffer;

                if (g_overlay_hwnd) {
                    SendMessageA(g_overlay_hwnd, WM_HYPRWIN_IPC, 0, reinterpret_cast<LPARAM>(&msg));
                } else {
                    msg.response = "ERROR: Overlay unavailable";
                }

                DWORD bytesWritten = 0;
                WriteFile(hPipe, msg.response.data(), static_cast<DWORD>(msg.response.size()), &bytesWritten, nullptr);
            }
        }
        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
    }
}


static FILETIME g_prev_idle_time = {0};
static FILETIME g_prev_kernel_time = {0};
static FILETIME g_prev_user_time = {0};

LRESULT CALLBACK TopbarWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  // УДАЛЕНО: topbar больше не нужен
  return DefWindowProcA(hwnd, msg, wParam, lParam);
}


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
  if (!IsWindow(hwnd)) return false;

  DWORD pid;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == GetCurrentProcessId()) return false;

  long style = GetWindowLong(hwnd, GWL_STYLE);
  long ex_style = GetWindowLong(hwnd, GWL_EXSTYLE);
  HWND owner = GetWindow(hwnd, GW_OWNER);

  if (ex_style & WS_EX_TOPMOST) return false;
  if (ex_style & WS_EX_TOOLWINDOW) return false;

  // Detect borderless/fullscreen exclusive game windows to prevent HyprWin from forcing tiling
  if ((style & WS_POPUP) && !(style & WS_CAPTION)) {
    RECT rc;
    GetWindowRect(hwnd, &rc);
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    if (rc.left <= 0 && rc.top <= 0 && rc.right >= screen_w && rc.bottom >= screen_h) {
      return false; // Treat fullscreen game windows as untracked standalone
    }
  }

  bool isAppWindow = (ex_style & WS_EX_APPWINDOW) != 0;
  bool isTopLevel = (style & WS_CAPTION) && (owner == NULL);

  if (!isAppWindow && !isTopLevel) return false;

  int cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
    return false;
  }

  return true;
}

void RestoreAllWindows() {
  static int offset = 0;
  EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
    if (IsWindowVisible(hwnd) && IsToplevelWindow(hwnd)) {
      // Сбрасываем прозрачность всех окон обратно на 100% (255)
      SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

      RECT rc;
      GetWindowRect(hwnd, &rc);
      // Если окно было на скрытом воркспейсе — возвращаем его на экран каскадом
      if (rc.left < -10000 || rc.top < -10000) {
        int* off = (int*)lParam;
        SetWindowPos(hwnd, HWND_NOTOPMOST, 100 + *off, 100 + *off, 1280, 720, 
                     SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        *off = (*off + 30) % 200;
      }
    }
    return TRUE;
  }, (LPARAM)&offset);
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
  if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == nullptr) return;
  if (event == 0x800B || event == 0x800A) return;

  HWND root = GetAncestor(hwnd, GA_ROOT);
  if (root != nullptr) hwnd = root;

  bool is_removal = (event == EVENT_OBJECT_DESTROY || event == EVENT_SYSTEM_MINIMIZESTART);

  if (!is_removal) {
    if (!IsWindowVisible(hwnd) || !IsToplevelWindow(hwnd)) return;
  }

  if (g_lua) {
    char title[256] = {0};
    GetWindowTextA(hwnd, title, sizeof(title));

    std::lock_guard<std::mutex> lock(g_lua_mutex);
    sol::protected_function dispatcher = (*g_lua)["HyprWin"]["dispatch_event"];
    if (dispatcher.valid()) {
      dispatcher(event, reinterpret_cast<size_t>(hwnd), std::string(title));
    }
  }
}

std::string GetConfigPath() {
    char szPath[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_PROFILE, NULL, 0, szPath))) {
        fs::path configDir = fs::path(szPath) / ".hyprwin";
        if (!fs::exists(configDir)) {
            fs::create_directory(configDir);
        }
        return (configDir / "hyprland.lua").string(); // Now returns hyprland.lua
    }
    return "hyprland.lua";
}

void EnsureDefaultConfig(const std::string& path) {
    if (!fs::exists(path)) {
        std::ofstream outFile(path);
        outFile << "-- HyprWin User Configuration" << std::endl; // Barebones empty template
        outFile.close();
    }
}

int main() {
  try {
    SetConsoleCtrlHandler(ConsoleHandler, TRUE);
    std::cout << "HyprWin: Initializing Lua engine..." << std::endl;
    std::string configPath = GetConfigPath();
    EnsureDefaultConfig(configPath);

    sol::state lua;
    g_lua = &lua;

    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::string,
                       sol::lib::math, sol::lib::table, sol::lib::os, sol::lib::io, sol::lib::debug);

    lua.set_function("log", [](std::string message) {
      std::cout << "[LUA]: " << message << std::endl;
    });

    auto wm = lua.create_named_table("wm");

    wm.set_function("get_class_name", [](size_t hwnd) {
      char class_name[256] = {0};
      GetClassNameA((HWND)hwnd, class_name, sizeof(class_name));
      return std::string(class_name);
    });

    wm.set_function("register_hotkey", [](int id, int modifiers, int vk) {
      UnregisterHotKey(NULL, id);
      if (RegisterHotKey(NULL, id, modifiers, vk)) {
        g_registered_hotkeys.push_back(id);
        return true;
      }
      return false;
    });

    wm.set_function("close_window", [](size_t hwnd) {
      PostMessage((HWND)hwnd, WM_CLOSE, 0, 0);
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

    wm.set_function("is_toplevel", [](size_t hwnd) {
      return IsToplevelWindow(reinterpret_cast<HWND>(hwnd));
    });

    wm.set_function("get_foreground_window", []() {
      return (size_t)GetForegroundWindow();
    });

    wm.set_function("is_maximized", [](size_t hwnd) {
      return (bool)IsZoomed((HWND)hwnd);
    });

    wm.set_function("maximize_window", [](size_t hwnd, bool state) {
      ShowWindow((HWND)hwnd, state ? SW_MAXIMIZE : SW_RESTORE);
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
      if (!IsWindow(handle)) return;

      if (IsIconic(handle)) {
        ShowWindow(handle, SW_RESTORE);
      } else {
        ShowWindow(handle, SW_SHOW);
      }

      HWND fg = GetForegroundWindow();
      DWORD fgThread = GetWindowThreadProcessId(fg, NULL);
      DWORD currentThread = GetCurrentThreadId();

      SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, (LPVOID)0, SPIF_SENDCHANGE);

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

    wm.set_function("set_window_opacity", [](size_t hwnd, double opacity) {
      HWND handle = reinterpret_cast<HWND>(hwnd);
      if (!IsWindow(handle)) return;

      LONG ex_style = GetWindowLong(handle, GWL_EXSTYLE);

      if (opacity >= 0.999) {
        if (ex_style & WS_EX_LAYERED) {
          SetWindowLong(handle, GWL_EXSTYLE, ex_style & ~WS_EX_LAYERED);
          SetWindowPos(handle, NULL, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
      } else {
        if (!(ex_style & WS_EX_LAYERED)) {
          SetWindowLong(handle, GWL_EXSTYLE, ex_style | WS_EX_LAYERED);
          SetWindowPos(handle, NULL, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
        BYTE alpha = static_cast<BYTE>(opacity * 255.0);
        SetLayeredWindowAttributes(handle, 0, alpha, LWA_ALPHA);
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

    wm.set_function("move_window", [](size_t hwnd, double x, double y, double w, double h) {
      HWND handle = reinterpret_cast<HWND>(hwnd);
      if (IsZoomed(handle)) ShowWindow(handle, SW_RESTORE);

      RECT windowRect;
      GetWindowRect(handle, &windowRect);

      RECT frameRect;
      bool is_stashed = (x < -10000 || y < -10000);
      if (!is_stashed && SUCCEEDED(DwmGetWindowAttribute(handle, DWMWA_EXTENDED_FRAME_BOUNDS, &frameRect, sizeof(RECT)))) {
        int leftMargin = frameRect.left - windowRect.left;
        int topMargin = frameRect.top - windowRect.top;
        int rightMargin = windowRect.right - frameRect.right;
        int bottomMargin = windowRect.bottom - frameRect.bottom;

        SetWindowPos(handle, HWND_NOTOPMOST,
                     static_cast<int>(x) - leftMargin,
                     static_cast<int>(y) - topMargin,
                     static_cast<int>(w) + leftMargin + rightMargin,
                     static_cast<int>(h) + topMargin + bottomMargin,
                     SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING);
      } else {
        SetWindowPos(handle, HWND_NOTOPMOST,
                     static_cast<int>(x),
                     static_cast<int>(y),
                     static_cast<int>(w),
                     static_cast<int>(h),
                     SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING);
      }
    });

    wm.set_function("get_screen_size", []() {
      return std::make_pair(GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
    });

    wm.set_function("get_window_rect", [](size_t hwnd) {
      RECT rect = {0};
      if (SUCCEEDED(DwmGetWindowAttribute((HWND)hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rect, sizeof(RECT)))) {
        return std::make_tuple((int)rect.left, (int)rect.top,
                               (int)(rect.right - rect.left),
                               (int)(rect.bottom - rect.top));
      }
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

    wm.set_function("is_minimized", [](size_t hwnd) {
      return (bool)IsIconic((HWND)hwnd);
    });

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

    wm.set_function("get_config_path", [configPath]() {
      return configPath;
    });

    auto ui = lua.create_named_table("ui");

    ui.set_function("draw_rect", [](float x, float y, float w, float h, float r, float g, float b, float a, float thickness) {
      if (g_current_renderer) g_current_renderer->draw_rect(x, y, w, h, r, g, b, a, thickness);
    });
    ui.set_function("fill_rect", [](float x, float y, float w, float h, float r, float g, float b, float a) {
      if (g_current_renderer) g_current_renderer->fill_rect(x, y, w, h, r, g, b, a);
    });
    ui.set_function("draw_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a, float thick) {
      if (g_current_renderer) g_current_renderer->draw_rounded_rect(x, y, w, h, rad, r, g, b, a, thick);
    });
    ui.set_function("fill_rounded_rect", [](float x, float y, float w, float h, float rad, float r, float g, float b, float a) {
      if (g_current_renderer) g_current_renderer->fill_rounded_rect(x, y, w, h, rad, r, g, b, a);
    });
    ui.set_function("draw_text", [](std::string text, float x, float y, float size, float r, float g, float b, float a, std::string font) {
      if (g_current_renderer) g_current_renderer->draw_text(text, x, y, size, r, g, b, a, font);
    });
    ui.set_function("measure_text", [](std::string text, float size, std::string font) {
      if (g_current_renderer) return g_current_renderer->measure_text_width(text, size, font);
      return 0.0f;
    });
    ui.set_function("render", []() {});

    WNDCLASSEXA wc = {sizeof(WNDCLASSEXA),
                      CS_HREDRAW | CS_VREDRAW,
                      OverlayWndProc,
                      0,
                      0,
                      GetModuleHandle(NULL),
                      NULL,
                      NULL,
                      (HBRUSH)GetStockObject(BLACK_BRUSH),
                      NULL,
                      "HyprWinOverlay",
                      NULL};
    RegisterClassExA(&wc);

    HWND overlay_hwnd = CreateWindowExA(
        WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_LAYERED, "HyprWinOverlay",
        "Overlay", WS_POPUP, 0, 0, GetSystemMetrics(SM_CXSCREEN),
        GetSystemMetrics(SM_CYSCREEN), NULL, NULL, wc.hInstance, NULL);

    g_overlay_hwnd = overlay_hwnd;

    SetLayeredWindowAttributes(overlay_hwnd, 0, 255, LWA_ALPHA);

    MARGINS margins = {-1};
    DwmExtendFrameIntoClientArea(overlay_hwnd, &margins);

    if (!g_renderer.init(overlay_hwnd)) {
      std::cerr << "HyprWin: Failed to initialize Renderer!" << std::endl;
      return -1;
    }

    ShowWindow(overlay_hwnd, SW_SHOW);
    SetWindowPos(overlay_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

    char buffer[MAX_PATH];
    GetModuleFileNameA(NULL, buffer, MAX_PATH);
    std::string path(buffer);
    std::string exe_dir = path.substr(0, path.find_last_of("\\/"));
    std::string script_path = exe_dir + "\\scripts\\main.lua";

    std::cout << "HyprWin: Loading script from " << script_path << std::endl;

    sol::protected_function_result result = lua.script_file(script_path);
    if (!result.valid()) {
      sol::error err = result;
      std::cerr << "!!! LUA SCRIPT ERROR: Failed to load/run " << script_path << std::endl;
      std::cerr << "Details: " << err.what() << std::endl;
      return 1;
    }

    HWINEVENTHOOK hook_objects =
        SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_NAMECHANGE, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    HWINEVENTHOOK hook_focus =
        SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL,
                        WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    HWINEVENTHOOK hook_minimize =
        SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND,
                        NULL, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);

    if (!hook_objects || !hook_focus || !hook_minimize) {
      std::cerr << "HyprWin: Failed to register WinEventHooks!" << std::endl;
      return 1;
    }

    if (!InitializeAltTabHook()) {
      std::cerr << "HyprWin: Failed to register low-level Keyboard hook!" << std::endl;
      return 1;
    }

    std::thread(IPCServerThread).detach();

    for (int i = 1; i <= 9; ++i) {
      RegisterHotKey(NULL, 101 + (i - 1), MOD_ALT, '0' + i);
      RegisterHotKey(NULL, 201 + (i - 1), MOD_ALT | MOD_SHIFT, '0' + i);
    }
    RegisterHotKey(NULL, 302, MOD_ALT, 'P');
    RegisterHotKey(NULL, 303, MOD_ALT, 'T');
    RegisterHotKey(NULL, 304, MOD_ALT, 'M');
    RegisterHotKey(NULL, 305, MOD_ALT, 'D');
    RegisterHotKey(NULL, 306, MOD_ALT, VK_RETURN);

    RegisterHotKey(NULL, 401, MOD_ALT, 'H');
    RegisterHotKey(NULL, 402, MOD_ALT, 'J');
    RegisterHotKey(NULL, 403, MOD_ALT, 'K');
    RegisterHotKey(NULL, 404, MOD_ALT, 'L');

    RegisterHotKey(NULL, 501, MOD_ALT | MOD_SHIFT, 'H');
    RegisterHotKey(NULL, 502, MOD_ALT | MOD_SHIFT, 'J');
    RegisterHotKey(NULL, 503, MOD_ALT | MOD_SHIFT, 'K');
    RegisterHotKey(NULL, 504, MOD_ALT | MOD_SHIFT, 'L');

    RegisterHotKey(NULL, 601, MOD_CONTROL | MOD_ALT, 'H');
    RegisterHotKey(NULL, 603, MOD_CONTROL | MOD_ALT, 'J');
    RegisterHotKey(NULL, 604, MOD_CONTROL | MOD_ALT, 'K');
    RegisterHotKey(NULL, 602, MOD_CONTROL | MOD_ALT, 'L');

    MSG msg;
    using clock = std::chrono::steady_clock;
    auto last_frame = clock::now();
    const std::chrono::nanoseconds frame_target(16666666);

    bool running = true;
    while (running) {
      while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) {
          running = false;
          break;
        }

        if (msg.message == WM_HOTKEY && g_lua) {
          std::lock_guard<std::mutex> lock(g_lua_mutex);
          sol::protected_function on_hotkey = (*g_lua)["HyprWin"]["on_hotkey"];
          if (on_hotkey.valid()) on_hotkey(static_cast<int>(msg.wParam));
        }
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
      }
      if (!running) break;

      auto now = clock::now();
      if (now - last_frame < frame_target) {
        Sleep(1);
        continue;
      }
      last_frame = now;

      HWND fg = GetForegroundWindow();
      bool is_fullscreen = false;

      if (fg && fg != g_overlay_hwnd && !IsZoomed(fg)) {
        char cls[256] = {0};
        GetClassNameA(fg, cls, sizeof(cls));
        if (strcmp(cls, "WorkerW") != 0 && strcmp(cls, "Progman") != 0 && strcmp(cls, "Shell_TrayWnd") != 0) {
          RECT rc;
          if (SUCCEEDED(DwmGetWindowAttribute(fg, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof(rc)))) {
            is_fullscreen = (rc.left <= 0 && rc.top <= 0 && 
                             rc.right >= GetSystemMetrics(SM_CXSCREEN) && 
                             rc.bottom >= GetSystemMetrics(SM_CYSCREEN));
          }
        }
      }

      if (is_fullscreen) {
        if (IsWindowVisible(g_overlay_hwnd)) ShowWindow(g_overlay_hwnd, SW_HIDE);
      } else {
        if (!IsWindowVisible(g_overlay_hwnd)) ShowWindow(g_overlay_hwnd, SW_SHOWNOACTIVATE);
      }

      if (IsWindowVisible(g_overlay_hwnd)) {
        g_current_renderer = &g_renderer;
        g_renderer.begin_draw();
        g_renderer.clear(0, 0, 0, 0);

        if (g_lua) {
          std::lock_guard<std::mutex> lock(g_lua_mutex);
          sol::protected_function render = (*g_lua)["HyprWin"]["on_render_overlay"];
          if (render.valid()) render();
        }

        g_renderer.end_draw();
      }
    }

    for (int i = 101; i <= 109; ++i) UnregisterHotKey(NULL, i);
    for (int id : g_registered_hotkeys) UnregisterHotKey(NULL, id);
    for (int i = 201; i <= 209; ++i) UnregisterHotKey(NULL, i);
    for (int i = 302; i <= 306; ++i) UnregisterHotKey(NULL, i);
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
    return 1;
  } catch (const std::exception &e) {
    std::cerr << "!!! SYSTEM ERROR: " << e.what() << std::endl;
    return 1;
  } catch (...) {
    std::cerr << "!!! UNKNOWN CRASH !!!" << std::endl;
    return 1;
  }

  return 0;
}