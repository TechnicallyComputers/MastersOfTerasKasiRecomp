cmake_minimum_required(VERSION 3.20)
project(MastersOfTerasKasiRecomp C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/psxrecomp" CACHE PATH
    "Path to psxrecomp")

include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

# Split-TU build: pick up sharded full_*.c if present, else the monolithic full.c.
file(GLOB MOTK_GENERATED_FULL_SHARDS CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/SLUS_005.62_full_*.c")
if(MOTK_GENERATED_FULL_SHARDS)
    set(MOTK_GENERATED_FULL "${MOTK_GENERATED_FULL_SHARDS}")
else()
    set(MOTK_GENERATED_FULL
        "${CMAKE_CURRENT_SOURCE_DIR}/generated/SLUS_005.62_full.c")
endif()
set(MOTK_GENERATED_DISPATCH
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/SLUS_005.62_dispatch.c")

psxrecomp_add_runtime_target(psx-runtime
    GAME_GENERATED_FULL_C "${MOTK_GENERATED_FULL}"
    GAME_GENERATED_DISPATCH_C "${MOTK_GENERATED_DISPATCH}"
    DEBUG_PORT 4520
    WINDOW_TITLE "Masters of Teras Kasi Recompiled"
    DEFAULT_BIOS_PATH "${PSXRECOMP_ROOT}/bios/SCPH1001.BIN"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
)
