# DualDS emulator core: upstream melonDS (unmodified, git submodule) + the DualDS session layer.
# Builds for iOS / iOS Simulator (see Scripts/build-core.sh) and for the host, where it also
# builds the headless core test runner.
cmake_minimum_required(VERSION 3.20)
project(DualDSCore LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# melonDS options DualDS relies on. JIT is off because App Store apps cannot map writable+executable
# memory; OpenGL is off because iOS uses Metal; the GDB stub and Qt/SDL frontend are desktop-only.
set(ENABLE_JIT OFF CACHE BOOL "" FORCE)
set(ENABLE_OGLRENDERER OFF CACHE BOOL "" FORCE)
set(ENABLE_GDBSTUB OFF CACHE BOOL "" FORCE)
set(BUILD_QT_SDL OFF CACHE BOOL "" FORCE)

add_subdirectory(melonDS EXCLUDE_FROM_ALL)

add_library(dualdscore STATIC
    DualDSCore/src/DSSession.cpp
    DualDSCore/src/DSPlatform.cpp)
target_include_directories(dualdscore PUBLIC DualDSCore/include)
# Upstream headers are included as system headers so -Wall reports only DualDS code.
target_include_directories(dualdscore SYSTEM PRIVATE melonDS/src)
target_link_libraries(dualdscore PUBLIC core)
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(dualdscore PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

if (NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_testing()
    add_executable(dualds_core_tests ../Tests/EmulatorCoreTests/core_tests.cpp)
    target_link_libraries(dualds_core_tests PRIVATE dualdscore)
    find_package(Threads REQUIRED)
    target_link_libraries(dualds_core_tests PRIVATE Threads::Threads)
    # Headless ROM player for automated FoldPlay Originals tests (scripted input -> PNG screenshots).
    find_package(ZLIB REQUIRED)
    add_executable(rom_player ../Tests/RomPlayer/rom_player.cpp)
    target_link_libraries(rom_player PRIVATE dualdscore Threads::Threads ZLIB::ZLIB)
    add_test(NAME core_tests
             COMMAND dualds_core_tests ${CMAKE_CURRENT_SOURCE_DIR}/../Tests/Fixtures/testrom/dualds-test.nds)
endif()
