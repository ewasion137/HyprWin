#include "../include/alttab.hpp"
#include <windows.h>

#define WM_HYPRWIN_ALTTAB (WM_USER + 501)

extern HWND g_overlay_hwnd;

static HHOOK g_keyboard_hook = NULL;
static bool g_alttab_active = false;

// Asynchronous low-level keyboard hook procedure
static LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION) {
    KBDLLHOOKSTRUCT *p = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);

    // Ignore injected/synthetic events to prevent recursion from wm.focus_window
    if (p->flags & LLKHF_INJECTED) {
      return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
    }

    bool alt_is_down = (p->flags & LLKHF_ALTDOWN) || ((GetKeyState(VK_MENU) & 0x8000) != 0);

    // Intercept Alt + Tab
    if (p->vkCode == VK_TAB && alt_is_down) {
      if (wParam == WM_SYSKEYDOWN || wParam == WM_KEYDOWN) {
        g_alttab_active = true;
        bool shift_is_down = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

        // Post asynchronously to overlay window queue to never block WH_KEYBOARD_LL
        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
          PostMessageA(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, shift_is_down ? 1 : 0, 0);
        }
        return 1; // Suppress native Windows Alt+Tab dialog
      }
    }

    // Release of ALT key triggers commit
    if ((p->vkCode == VK_MENU || p->vkCode == VK_LMENU || p->vkCode == VK_RMENU) && g_alttab_active) {
      if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
        g_alttab_active = false;
        if (g_overlay_hwnd && IsWindow(g_overlay_hwnd)) {
          PostMessageA(g_overlay_hwnd, WM_HYPRWIN_ALTTAB, 2, 0); // 2 = Commit
        }
      }
    }
  }
  return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

bool InitializeAltTabHook() {
  if (g_keyboard_hook) return true;
  g_keyboard_hook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc, GetModuleHandle(NULL), 0);
  return g_keyboard_hook != NULL;
}

void CleanupAltTabHook() {
  if (g_keyboard_hook) {
    UnhookWindowsHookEx(g_keyboard_hook);
    g_keyboard_hook = NULL;
  }
  g_alttab_active = false;
}