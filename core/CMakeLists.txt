# Define the core library
add_library(core_lib STATIC src/main.cpp)

# Link headers
target_include_directories(core_lib PUBLIC include)