cmake_minimum_required(VERSION 3.20)
project(MastersOfTerasKasiRecomp C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

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
# Profiles land in ${CMAKE_BINARY_DIR}/pgo/ (see scripts/pgo_motk_intro.sh).
# GCC: .gcda under PSX_PGO_DIR. Clang/AppleClang: .profraw → merge to
# PSX_PGO_DIR/default.profdata before -DPSX_PGO=use (CI does this).
# Setup-host CI must not set PSX_PGO — PGO is user-local after Generate.
set(PSX_PGO "" CACHE STRING "PGO mode: empty | generate | use")
set(PSX_PGO_DIR "${CMAKE_BINARY_DIR}/pgo" CACHE PATH "PGO profile directory")
if(PSX_PGO STREQUAL "generate")
    file(MAKE_DIRECTORY "${PSX_PGO_DIR}")
    if(CMAKE_C_COMPILER_ID MATCHES "Clang")
        add_compile_options(-fprofile-instr-generate)
        add_link_options(-fprofile-instr-generate)
    else()
        add_compile_options(-fprofile-generate=${PSX_PGO_DIR})
        add_link_options(-fprofile-generate=${PSX_PGO_DIR})
    endif()
elseif(PSX_PGO STREQUAL "use")
    if(CMAKE_C_COMPILER_ID MATCHES "Clang")
        set(_psx_pgo_profdata "${PSX_PGO_DIR}/default.profdata")
        if(NOT EXISTS "${_psx_pgo_profdata}")
            message(FATAL_ERROR
                "PSX_PGO=use (Clang): missing ${_psx_pgo_profdata}. "
                "Train with LLVM_PROFILE_FILE=.../pgo/motk-%p.profraw then "
                "llvm-profdata merge -o default.profdata *.profraw")
        endif()
        add_compile_options("-fprofile-instr-use=${_psx_pgo_profdata}")
        add_link_options("-fprofile-instr-use=${_psx_pgo_profdata}")
    else()
        # After source edits, GCC floods -Wcoverage-mismatch / -Wmissing-profile
        # against a stale .gcda set. Keep best-effort use (-fprofile-correction)
        # but don't spam the build log — retrain via scripts/pgo_motk_intro.sh
        # when you want fresh profiles.
        add_compile_options(
            -fprofile-use=${PSX_PGO_DIR}
            -fprofile-correction
            -Wno-coverage-mismatch
            -Wno-missing-profile
        )
        add_link_options(-fprofile-use=${PSX_PGO_DIR})
    endif()
endif()

set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/psxrecomp" CACHE PATH
    "Path to psxrecomp")
# MotK is a rollback-netplay title: opt in before include(runtime.cmake) so
# recomp-net is discovered/linked at parse time (ENABLE_NETPLAY_IF_PRESENT
# alone is too late — option(PSX_NETPLAY) already ran OFF).
if(EXISTS "${PSXRECOMP_ROOT}/lib/recomp-net/CMakeLists.txt")
    set(PSX_NETPLAY ON CACHE BOOL
        "Link recomp-net delay-sync (opt-in; needs recomp-net)" FORCE)
endif()
# Self-build first-run wizard + Generate & rebuild (tested on MotK).
set(PSX_SETUP_WIZARD ON CACHE BOOL
    "Advertise first-run setup wizard + Generate & rebuild in recomp-ui" FORCE)
include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

psxrecomp_add_game_runtime(psx-runtime
    ENABLE_NETPLAY_IF_PRESENT
    ENABLE_SETUP_WIZARD
    WINDOW_TITLE "Masters of Teras Kasi Recompiled"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
    LAUNCHER_BOXART "${CMAKE_CURRENT_SOURCE_DIR}/launcher_assets/img/boxart.tga"
    DEBUG_PORT 4520
    MAX_PLAYERS 2
    GEN_MARKER "generated/SLUS_005.62_dispatch.c"
    GEN_FULL_GLOB "generated/SLUS_005.62_full_*.c"
    GEN_FULL_FALLBACK "generated/SLUS_005.62_full.c"
    CODEGEN_SETUP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/codegen_setup.c"
)
