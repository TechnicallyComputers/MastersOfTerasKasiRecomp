cmake_minimum_required(VERSION 3.20)
project(MastersOfTerasKasiRecomp C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

# Cross-TU inlining for MotK VLC/decode hot paths (psx_cyc_*, interrupt checks).
# Release-only — Debug/RelWithDebInfo stay easier to step.
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)

# Tune for the build host (MotK FMV is load-delay / VLC host-bound).
add_compile_options($<$<CONFIG:Release>:-march=native> $<$<CONFIG:Release>:-mtune=native>)

# Profile-guided optimization for MotK intro FMV host path.
#   cmake -DPSX_PGO=generate ... && ninja && run intro ~60s
#   cmake -DPSX_PGO=use ... && ninja
# Profiles land in build-release/pgo/ (see scripts/pgo_motk_intro.sh).
set(PSX_PGO "" CACHE STRING "PGO mode: empty | generate | use")
set(PSX_PGO_DIR "${CMAKE_BINARY_DIR}/pgo" CACHE PATH "PGO profile directory")
if(PSX_PGO STREQUAL "generate")
    file(MAKE_DIRECTORY "${PSX_PGO_DIR}")
    add_compile_options(-fprofile-generate=${PSX_PGO_DIR})
    add_link_options(-fprofile-generate=${PSX_PGO_DIR})
elseif(PSX_PGO STREQUAL "use")
    add_compile_options(-fprofile-use=${PSX_PGO_DIR} -fprofile-correction)
    add_link_options(-fprofile-use=${PSX_PGO_DIR})
endif()

set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/psxrecomp" CACHE PATH
    "Path to psxrecomp")

# Delay-sync netplay (recomp-net). Auto-discovered as ../recomp-net by
# runtime.cmake when present. Lobby menu / matchmaking server are later work.
# Disable with -DPSX_NETPLAY=OFF.

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
    DEFAULT_GAME_CONFIG_PATH "game.toml"
)
