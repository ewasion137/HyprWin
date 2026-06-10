#include "../include/alttab.hpp"
#include <sol/sol.hpp>
#include <iostream>

extern sol::state *g_lua; // Declared in main.cpp

HHOOK g_keyboard_hook = NULL;
bool g_alttab_active = false;

// Low-level keyboard hook procedure
LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION) {
    KBDLLHOOKSTRUCT *p = (KBDLLHOOKSTRUCT *)lParam;

    // Check if ALT is currently pressed
    bool alt_is_down = (p->flags & LLKHF_ALTDOWN) || (GetKeyState(VK_MENU) & 0x8000);

    // Handle Tab key while ALT is held down
    if (p->vkCode == VK_TAB && alt_is_down) {
      if (wParam == WM_SYSKEYDOWN || wParam == WM_KEYDOWN) {
        g_alttab_active = true;
        
        if (g_lua) {
          sol::protected_function alttab_func = (*g_lua)["HyprWin"]["on_alttab_action"];
          if (alttab_func.valid()) {
            // Check if Shift is also held down for reverse cycling
            bool shift_is_down = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            auto result = alttab_func(shift_is_down ? "prev" : "next");
            if (!result.valid()) {
              sol::error err = result;
              std::cerr << "!!! LUA ALTTAB ERROR: " << err.what() << std::endl;
            }
          }
        }
        return 1; // Block default Windows Alt+Tab dialog from appearing
      }
    }

    // Handle ALT key release to commit the selection and close menu
    if ((p->vkCode == VK_MENU || p->vkCode == VK_LMENU || p->vkCode == VK_RMENU) && g_alttab_active) {
      if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
        g_alttab_active = false;

        if (g_lua) {
          sol::protected_function alttab_func = (*g_lua)["HyprWin"]["on_alttab_action"];
          if (alttab_func.valid()) {
            auto result = alttab_func("commit");
            if (!result.valid()) {
              sol::error err = result;
              std::cerr << "!!! LUA ALTTAB ERROR: " << err.what() << std::endl;
            }
          }
        }
      }
    }
  }
  return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

bool InitializeAltTabHook() {
  g_keyboard_hook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc, GetModuleHandle(NULL), 0);
  return g_keyboard_hook != NULL;
}

void CleanupAltTabHook() {
  if (g_keyboard_hook) {
    UnhookWindowsHookEx(g_keyboard_hook);
    g_keyboard_hook = NULL;
  }
}