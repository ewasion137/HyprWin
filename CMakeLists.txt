cmake_minimum_required(VERSION 3.20)
project(HyprWin VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Just include, don't build core as separate binary yet if it's empty
add_subdirectory(core)

# Main executable
add_executable(HyprWin core/src/main.cpp)

target_link_libraries(HyprWin PRIVATE core_lib user32 dwmapi dcomp)