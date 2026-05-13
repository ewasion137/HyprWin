#ifndef NOMINMAX
#define NOMINMAX // Prevents Windows.h from defining min/max macros
#endif

#include <dwmapi.h>
#include <iostream>
#include <limits>
#include <windows.h>


int main() {
  std::cout << "HyprWin: Core initialized." << std::endl;

  BOOL enabled = FALSE;
  DwmIsCompositionEnabled(&enabled);

  std::cout << "HyprWin: DWM composition is "
            << (enabled ? "ENABLED" : "DISABLED") << std::endl;

  std::cout << "\nPress Enter to exit..." << std::endl;
  std::cin.clear();
  // Use parentheses to avoid macro collision even with NOMINMAX
  std::cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
  std::cin.get();

  return 0;
}