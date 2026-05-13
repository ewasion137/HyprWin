#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <iostream>
#include <sol/sol.hpp> // The magic bridge
#include <windows.h>


int main() {
  std::cout << "HyprWin: Initializing Lua engine..." << std::endl;

  // Initialize Lua state
  sol::state lua;
  lua.open_libraries(sol::lib::base);

  // Let's create a simple function in C++ that Lua can call
  lua.set_function("log", [](std::string message) {
    std::cout << "[LUA]: " << message << std::endl;
  });

  // Run a test script
  try {
    lua.script("log('HyprWin Lua bridge is alive!')");
  } catch (const sol::error &e) {
    std::cerr << "Lua Error: " << e.what() << std::endl;
  }

  std::cout << "Press Enter to exit..." << std::endl;
  std::cin.get();

  return 0;
}