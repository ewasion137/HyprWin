#pragma once
#include <windows.h>

// Initialize and start the low-level keyboard hook for Alt+Tab interception
bool InitializeAltTabHook();

// Release the low-level keyboard hook
void CleanupAltTabHook();