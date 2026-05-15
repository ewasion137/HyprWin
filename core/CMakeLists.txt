# Collect all source and header files recursively
file(GLOB_RECURSE CORE_SOURCES "src/*.cpp")
file(GLOB_RECURSE CORE_HEADERS "include/*.hpp")

# Remove main.cpp from library sources to avoid double-definition (it's used in root)
list(REMOVE_ITEM CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/main.cpp")

# Define the core library with all found files
add_library(core_lib STATIC ${CORE_SOURCES} ${CORE_HEADERS})

# Link headers
target_include_directories(core_lib PUBLIC include)