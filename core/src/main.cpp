#include <dwmapi.h> // Testing the Windows SDK integration
#include <iostream>
#include <windows.h>


int main() {
  std::cout << "HyprWin: Core initialized." << std::endl;

  // Simple check: get the DWM composition state
  BOOL enabled = FALSE;
  DwmIsCompositionEnabled(&enabled);

  std::cout << "HyprWin: DWM composition is "
            << (enabled ? "ENABLED" : "DISABLED") << std::endl;

  return 0;
}