/* Masters of Teras Kasi config for psxrecomp/host/psxrecomp_codegen_host. */

#include "codegen_setup.h"

#include "psxrecomp_codegen_host.h"

static const PsxrecompCodegenHostConfig kMotkCodegenConfig = {
    .display_name = "Masters of Teras Kasi",
    .project_root_env = "MOTK_PROJECT_ROOT",
    .build_dir_env = "MOTK_BUILD_DIR",
    .force_setup_env = "MOTK_FORCE_SETUP",
    .psxrecomp_cli_relpath = "psxrecomp/psxrecomp_cli.py",
    .seed_cfg_relpath = "game.toml",
    .game_toml_relpath = "game.toml",
    .gen_marker_relpath = "generated/SLUS_005.62_dispatch.c",
    .build_dir_name = "build-release",
    .cmake_target = "psx-runtime",
    .exe_basename = "Masters_of_Teras_Kasi_Recompiled",
    .prepare_note =
        "Uses your Masters of Teras Kasi (USA) disc with the local "
        "psxrecomp SDK to generate OpenBIOS (+ optional SCPH1001) and "
        "game C, then cmake --build and restart. You must legally own "
        "this disc.",
    .prepare_note_windows =
        "Uses your disc with the local psxrecomp SDK to generate BIOS + "
        "game C, then quits and rebuilds via a helper so the running "
        ".exe is not locked. You must legally own this disc.",
    .prepare_note_no_cmake =
        "Uses your disc with the local psxrecomp SDK to generate BIOS + "
        "game C. CMake/build dir not found — rebuild manually, then "
        "relaunch.",
};

void psx_game_codegen_setup_apply(RecompLauncherCGameInfo* gi) {
    psxrecomp_codegen_host_apply(gi, &kMotkCodegenConfig);
}

void psx_game_codegen_relaunch_or_exit(const char* disc_path) {
    psxrecomp_codegen_host_relaunch_or_exit(disc_path);
}
