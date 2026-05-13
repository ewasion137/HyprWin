#include <dwmapi.h>
#include <iostream>
#include <limits> // Required for cin.ignore
#include <windows.h>


int main() {
  std::cout << "HyprWin: Core initialized." << std::endl;

  BOOL enabled = FALSE;
  DwmIsCompositionEnabled(&enabled);

  std::cout << "HyprWin: DWM composition is "
            << (enabled ? "ENABLED" : "DISABLED") << std::endl;

  // Professional way to pause: wait for user input without system commands
  std::cout << "\nPress Enter to exit..." << std::endl;
  std::cin.clear();
  std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
  std::cin.get();

  return 0;
}