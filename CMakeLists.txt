cmake_minimum_required(VERSION 3.20)
project(HyprWin VERSION 0.1 LANGUAGES CXX)

# Set C++20 for modern features
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include core logic
add_subdirectory(core)

# Define the main executable
add_executable(HyprWin core/src/main.cpp)

# Link necessary Windows system libraries
target_link_libraries(HyprWin PRIVATE 
    user32 
    dwmapi 
    dcomp
)