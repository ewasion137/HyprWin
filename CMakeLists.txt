cmake_minimum_required(VERSION 3.20)
project(HyprWin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define paths
set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/core)
set(SCRIPTING_DIR ${CMAKE_CURRENT_SOURCE_DIR}/scripting)
set(LUA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lua)

# Include Lua headers
include_directories(${LUA_DIR}/src)

# Add Lua source files (Professional way: compile Lua with the project)
file(GLOB LUA_SOURCES "${LUA_DIR}/src/*.c")
# Remove lua.c and luac.c to avoid double main()
list(REMOVE_ITEM LUA_SOURCES "${LUA_DIR}/src/lua.c" "${LUA_DIR}/src/luac.c")

add_library(lua_lib STATIC ${LUA_SOURCES})

# HyprWin Executable
add_executable(${PROJECT_NAME} 
    core/src/main.cpp
    scripting/src/ScriptEngine.cpp
)

target_include_directories(${PROJECT_NAME} PRIVATE 
    ${CORE_DIR}/include 
    ${SCRIPTING_DIR}/include
)

target_link_libraries(${PROJECT_NAME} PRIVATE lua_lib)

# Setup output directory
set_target_properties(${PROJECT_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)