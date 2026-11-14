# Single-file launcher for the Windows build (see launcher.cpp).
# Built separately from the Flutter app:
#   cmake -S windows/onefile -B build/onefile -A x64
#   cmake --build build/onefile --config Release
cmake_minimum_required(VERSION 3.15)
project(taler_onefile LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(taler_onefile WIN32 launcher.cpp launcher.rc)
target_compile_definitions(taler_onefile PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(taler_onefile PRIVATE /utf-8 /W3)
target_link_libraries(taler_onefile PRIVATE shell32 ole32 user32 uuid)
set_target_properties(taler_onefile PROPERTIES OUTPUT_NAME "launcher")
