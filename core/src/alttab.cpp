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
    bool alt_is_down = (p->flags & LLKHF_ALTDOWN) || (GetKeyState(VK_MENU) & 0x8000);

    // Capture tab actions while alt is pressed
    if (p->vkCode == VK_TAB && alt_is_down) {
      if (wParam == WM_SYSKEYDOWN || wParam == WM_KEYDOWN) {
        g_alttab_active = true;
        bool shift_is_down = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        // 1 = next, 2 = prev
        PostMessage(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, shift_is_down ? 2 : 1, 0);
        return 1; // Prevent default Windows switcher
      }
    }

    // Capture alt release to commit
    if ((p->vkCode == VK_MENU || p->vkCode == VK_LMENU || p->vkCode == VK_RMENU) && g_alttab_active) {
      if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
        g_alttab_active = false;
        // 3 = commit
        PostMessage(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, 3, 0);
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