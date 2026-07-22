cmake_minimum_required(VERSION 3.20)
project(MastersOfTerasKasiRecomp C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

# Release version pin for netplay lobby matching (baked as PSX_GAME_VERSION).
# VERSION file at repo root is the source of truth for Release builds;
# Debug/RelWithDebInfo stay "dev" unless -DPSX_GAME_VERSION=... is passed.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" _MOTK_VER_RAW)
string(STRIP "${_MOTK_VER_RAW}" MOTK_RELEASE_VERSION)
set(PSX_GAME_VERSION "" CACHE STRING
    "Lobby release pin (empty = Release uses VERSION file, else dev)")
if(PSX_GAME_VERSION STREQUAL "")
    get_property(_motk_is_multi GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
    if(_motk_is_multi)
        # Release config → VERSION file; Debug/RelWithDebInfo → "dev".
        set(PSX_GAME_VERSION "$<IF:$<CONFIG:Release>,${MOTK_RELEASE_VERSION},dev>")
    elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
        set(PSX_GAME_VERSION "${MOTK_RELEASE_VERSION}")
    else()
        set(PSX_GAME_VERSION "dev")
    endif()
endif()
message(STATUS "MotK lobby game_version: ${PSX_GAME_VERSION} (from VERSION=${MOTK_RELEASE_VERSION})")

# Cross-TU inlining for MotK VLC/decode hot paths (psx_cyc_*, interrupt checks).
# Release-only — Debug/RelWithDebInfo stay easier to step.
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)

# Host-tuned codegen helps MotK FMV on the build machine, but breaks portable
# CI/release binaries. Default OFF; enable locally with -DMOTK_NATIVE=ON.
option(MOTK_NATIVE "Tune Release for the build host (-march=native)" OFF)
if(MOTK_NATIVE)
    add_compile_options(
        $<$<CONFIG:Release>:-march=native>
        $<$<CONFIG:Release>:-mtune=native>)
    message(STATUS "MotK: MOTK_NATIVE=ON (Release uses -march=native)")
endif()

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

# Prefer the framework-vendored recomp-net submodule (CI recursive checkout).
# Still overridable with -DRECOMP_NET_ROOT=…; disable with -DPSX_NETPLAY=OFF.
if(NOT RECOMP_NET_ROOT AND EXISTS "${PSXRECOMP_ROOT}/lib/recomp-net/CMakeLists.txt")
    set(RECOMP_NET_ROOT "${PSXRECOMP_ROOT}/lib/recomp-net" CACHE PATH
        "Path to recomp-net; empty = auto-discover" FORCE)
endif()

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
    LAUNCHER_BOXART "${CMAKE_CURRENT_SOURCE_DIR}/launcher_assets/img/boxart.tga"
    GAME_VERSION "${PSX_GAME_VERSION}"
)
