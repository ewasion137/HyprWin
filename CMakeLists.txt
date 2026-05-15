cmake_minimum_required(VERSION 3.20)
project(HyprWin VERSION 0.1 LANGUAGES CXX C) # Added C for Lua compilation
add_definitions(-DLUA_OPNAMES)
if(MSVC)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
endif()
set(CMAKE_CXX_STANDARD 20)

# Include paths
include_directories(third_party third_party/lua)

# Create a static library for Lua from its source files
file(GLOB ALL_LUA_SOURCES "third_party/lua/*.c")

set(LUA_SOURCES "")
foreach(SOURCE_FILE ${ALL_LUA_SOURCES})
    # Exclude files that define 'main'
    if(NOT "${SOURCE_FILE}" MATCHES "lua\\.c$" AND NOT "${SOURCE_FILE}" MATCHES "luac\\.c$")
        list(APPEND LUA_SOURCES ${SOURCE_FILE})
    endif()
endforeach()

add_library(lua_lib STATIC ${LUA_SOURCES})

# Main logic
add_subdirectory(core)

add_executable(HyprWin core/src/main.cpp)
target_link_libraries(HyprWin PRIVATE core_lib lua_lib user32 dwmapi dcomp d2d1)

# Copy scripts to the build directory for easy debugging
add_custom_command(TARGET HyprWin POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts"
    "$<TARGET_FILE_DIR:HyprWin>/scripts"
    COMMENT "Deploying scripts to executable directory"
)

# Future installation rules for Setup
install(TARGETS HyprWin RUNTIME DESTINATION .)
install(DIRECTORY scripts DESTINATION .)
