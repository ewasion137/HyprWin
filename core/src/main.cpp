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

    char buffer[MAX_PATH];
    GetModuleFileNameA(NULL, buffer, MAX_PATH);
    std::string path(buffer);
    std::string exe_dir = path.substr(0, path.find_last_of("\\/"));

    // Load the entry point script from the scripts folder
    std::string script_path = exe_dir + "\\scripts\\main.lua";

    std::cout << "HyprWin: Loading script from " << script_path << std::endl;

    auto result = lua.script_file(script_path);

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