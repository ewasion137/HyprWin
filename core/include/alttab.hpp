#pragma once
#include <windows.h>

#define WM_HYPRWIN_ALTTAB (WM_USER + 1)

// Initialize and start the low-level keyboard hook for Alt+Tab interception
bool InitializeAltTabHook();

// Release the low-level keyboard hook
void CleanupAltTabHook();