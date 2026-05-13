#include <iostream>
#include <windows.h>


// Entry point for a Windows application
int main() {
  // Notify the user that HyprWin is starting
  std::cout << "HyprWin: Initializing core..." << std::endl;

  // TODO: Initialize Lua state here
  // TODO: Setup WinEventHook for window management

  std::cout << "HyprWin: Core initialized successfully." << std::endl;

  return 0;
}