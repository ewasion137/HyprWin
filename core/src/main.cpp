#ifndef NOMINMAX
#define NOMINMAX
#endif

// 1. Включаем все защиты sol2 ПЕРЕД хедером
#define SOL_ALL_SAFETIES_ON 1

#include <iostream>
#include <windows.h>


// 2. Явно подключаем Lua с C-линковкой (на всякий случай)
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

}

#include <sol/sol.hpp>

int main() {
  // Wrap everything in a try-catch to catch sol2 exceptions
  try {
    std::cout << "HyprWin: Initializing Lua engine..." << std::endl;

    sol::state lua;

    // Open standard libraries safely
    lua.open_libraries(sol::lib::base, sol::lib::package);

    // Bind a C++ function to Lua
    lua.set_function("log", [](std::string message) {
      std::cout << "[LUA]: " << message << std::endl;
    });

    std::cout << "HyprWin: Running test script..." << std::endl;

    // Execute Lua code
    auto result = lua.script("log('HyprWin Lua bridge is alive!')");

    if (result.valid()) {
      std::cout << "HyprWin: Lua test passed." << std::endl;
    }

  } catch (const sol::error &e) {
    std::cerr << "!!! LUA ERROR: " << e.what() << std::endl;
  } catch (const std::exception &e) {
    std::cerr << "!!! SYSTEM ERROR: " << e.what() << std::endl;
  } catch (...) {
    std::cerr << "!!! UNKNOWN CRASH !!!" << std::endl;
  }

  std::cout << "\nPress Enter to exit..." << std::endl;
  std::cin.get();

  return 0;
}