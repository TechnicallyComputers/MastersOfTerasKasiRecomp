# MastersOfTerasKasiRecomp

*Star Wars: Masters of Teras Kasi* (USA, **SLUS-00562**, Oct 31, 1997) —
game project for [PSXRecomp](https://github.com/TechnicallyComputers/psxrecomp).

Holds game config, seeds, and build glue. Players Generate game C locally
(setup-host releases). Disc images and BIOS stay local and gitignored.

## Layout

| Path | Role |
|------|------|
| `game.toml` | Game / recompiler / runtime config |
| `seeds/` | Function-start seeds for `psxrecomp-game` |
| `motk/` | Local disc `.bin`/`.cue`, `SLUS_005.62`, `SYSTEM.CNF` (gitignored) |
| `psxrecomp/` | Framework submodule (`mstan/psxrecomp`; keeps `lib/recomp-net`) |
| `recomp-ui/` | Launcher UI submodule (`mstan/recomp-ui`) at game root |
| `generated/` | Local recompiler output (gitignored; first-run Generate / `psxrecomp-game`) |
| `VERSION` | Release / lobby match pin (e.g. `0.1.0`) |
| `DISC.md` | Disc identity + hashes |
| `tools/prepare_disc.py` | Stage Redump cue/bins into `motk/` (wraps framework prepare) |

## Disc

Canonical dump is the Redump-style multi-track USA cue (see `DISC.md`):

`/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA)/Star Wars - Masters of Teras Kasi (USA).cue`

Stage into `motk/` (preserves data + audio tracks, extracts boot EXE):

```bash
python3 tools/prepare_disc.py
```

## Bring-up (next steps)

1. Place `SCPH1001.BIN` under `psxrecomp/bios/` (or point the runtime at your BIOS).
2. Build the framework recompiler, then generate game C:

```bash
# from this repo, after psxrecomp/recompiler is built
./psxrecomp/recompiler/build/psxrecomp-game --config game.toml
```

3. Configure and build the runtime target. Prefer **Release** for playtesting
   (RelWithDebInfo turns on the TCP debug server and is much slower):

```bash
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
# Optional local FMV tune (do NOT use for release/CI packages):
#   -DMOTK_NATIVE=ON
cmake --build build-release --target psx-runtime -j"$(nproc)"

./build-release/Masters_of_Teras_Kasi_Recompiled \
  --game game.toml \
  --disc "motk/Star Wars - Masters of Teras Kasi (USA).cue"
```

For debugging (port **4520**), use `-DCMAKE_BUILD_TYPE=RelWithDebInfo` and
`./build/Masters_of_Teras_Kasi_Recompiled` instead.

### PGO (intro FMV host pace)

Profile-guided optimization trains the compiler on a real MotK intro run.
**Launcher:** Settings → SYSTEM → **Optimize FMV Playback** (after Generate
once). Peers may PGO independently for rollback. CLI one-shot:

```bash
DISPLAY=:0 ./scripts/pgo_motk_intro.sh
```

Full write-up: [docs/PGO.md](docs/PGO.md). After large runtime edits,
retrain so profiles stay fresh (`-DPSX_PGO=use` with stale `.gcda` underperforms).

## Docs

| Doc | Topic |
|-----|--------|
| [docs/PGO.md](docs/PGO.md) | Intro FMV profile-guided optimize |
| [psxrecomp/docs/NETPLAY.md](psxrecomp/docs/NETPLAY.md) | Netplay features (rollback, SFU/ICE, dual-raster, disc gates) |
| [psxrecomp/docs/GAME_PROJECT_SETUP.md](psxrecomp/docs/GAME_PROJECT_SETUP.md) | Title-repo layout, setup wizard / netplay build flags |
| [DISC.md](DISC.md) | Disc identity + hashes |
| [ISSUES.md](ISSUES.md) | Known bring-up issues |

## CI / release packages

Setup-host workflow (no generated C, no private CI assets, no PGO in CI).
Template: `psxrecomp/docs/ci/templates/setup-release.yml`.

| Artifact | Runner |
|----------|--------|
| `linux-x64` | `ubuntu-24.04` |
| `windows-x64` | `windows-2022` (MSYS2 MinGW64) |
| `macos-arm64` | `macos-15` |
| `macos-x64` | `macos-15-intel` (older Intel Macs) |

- Manual: **Actions → Release builds → Run workflow**
- Tag `v*` (matching `VERSION`): builds + GitHub Release with `motk-*.zip`
- Zip is a Generate & rebuild host: exe + sources + `psxrecomp-game` /
  `psxrecomp-bios` — never BIOS dumps, disc images, or prebuilt game C
- CI: `-DPSXRECOMP_FORCE_SETUP_HOST=ON -DPSX_NETPLAY=ON -DRNET_ENABLE_ICE=ON
  -DMOTK_NATIVE=OFF` (no `PSX_PGO`; ICE also defaults ON whenever
  `PSX_NETPLAY` is set via `runtime.cmake`)
- Local pack: `scripts/package_setup_release.sh build-ci linux-x64 build-recompiler`
- Full-player local packs (after Generate): `scripts/package_release.sh` still
  exists for optional use; CI no longer calls it
- PGO stays user-local after Generate (`scripts/pgo_motk_intro.sh`)
- **CachyOS/Arch → Fedora KDE test packs:** do **not** ship a native CachyOS
  binary (glibc 2.43+ will not load on Fedora 42’s glibc 2.41). From CachyOS:
  ```bash
  sudo pacman -S podman patchelf zip   # once
  scripts/build_for_fedora.sh          # Fedora 42 container build + lib/ bundle
  # → dist/motk-<VERSION>-linux-fedora42-bundled.zip
  ```
  Copy the zip to Fedora, unzip, `./run.sh`. If Browse BIOS dies before a
  dialog: `sudo dnf install kdialog`. (`FEDORA_TAG=41` for Fedora 41.)
- **Browse BIOS SIGSEGV capture:**  
  `scripts/debug_bios_browse_crash.sh [path-to-exe]`  
  Click Browse BIOS when the modal appears; gdb dumps `bt` / `bt full` to
  `dist/debug-bios-browse-crash-*.log` (handles LTO `.constprop` symbol names).
  Prefer a RelWithDebInfo build for readable frames.
- **Linux file picker:** recomp-ui uses `posix_spawn` of zenity/kdialog (not
  tinyfd `popen`/`vfork`) so Browse BIOS / Change ROM does not SIGSEGV under
  multithreaded SDL. Install `kdialog` (Fedora KDE) or `zenity`.

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/TechnicallyComputers/MastersOfTerasKasiRecomp.git
```

## Status

Boots far enough to present video/audio. Known bring-up costs: heavy dirty-RAM
interpretation (stuttery audio until more seeds/overlays land). See `ISSUES.md`.
