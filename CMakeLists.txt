cmake_minimum_required(VERSION 3.20)
project(HyprWin VERSION 0.1 LANGUAGES CXX C) # Added C for Lua compilation

set(CMAKE_CXX_STANDARD 20)

# Include paths
include_directories(third_party/sol third_party/lua)

# Create a static library for Lua from its source files
file(GLOB LUA_SOURCES "third_party/lua/*.c")
add_library(lua_lib STATIC ${LUA_SOURCES})

# Main logic
add_subdirectory(core)

add_executable(HyprWin core/src/main.cpp)
target_link_libraries(HyprWin PRIVATE core_lib lua_lib)