# MastersOfTerasKasiRecomp

*Star Wars: Masters of Teras Kasi* (USA, **SLUS-00562**, Oct 31, 1997) —
game project for [PSXRecomp](https://github.com/TechnicallyComputers/psxrecomp).

Holds game config, seeds, build glue, and (for private CI) recompiler
`generated/` output. Disc images and BIOS stay local and gitignored.

## Layout

| Path | Role |
|------|------|
| `game.toml` | Game / recompiler / runtime config |
| `seeds/` | Function-start seeds for `psxrecomp-game` |
| `motk/` | Local disc `.bin`/`.cue`, `SLUS_005.62`, `SYSTEM.CNF` (gitignored) |
| `psxrecomp/` | Framework submodule (`TechnicallyComputers/psxrecomp`) |
| `generated/` | Recompiler output (tracked for CI; regenerate when seeds change) |
| `VERSION` | Release / lobby match pin (e.g. `0.1.0`) |
| `DISC.md` | Disc identity + hashes |
| `tools/prepare_disc.py` | Rebuild `motk/` from the source 2448-byte dump |

## Disc

Source dump (2448-byte sectors with subchannel):

`/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA).iso`

Working image for the runtime is MODE2/2352 under `motk/`. Recreate with:

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

## CI / release packages

GitHub Actions workflow: `.github/workflows/release.yml`

| Artifact | Runner |
|----------|--------|
| `linux-x64` | `ubuntu-24.04` |
| `windows-x64` | `windows-2022` (MSYS2 MinGW64) |
| `macos-arm64` | `macos-15` |
| `macos-x64` | `macos-15-intel` (older Intel Macs) |

- Manual: **Actions → Release builds → Run workflow**
- Tag `v0.1.0` (matching `VERSION`): builds + GitHub Release with zips
- Packages include the exe, launcher assets, `game.toml`, and `VERSION` — never BIOS/disc
- Local pack: `scripts/package_release.sh build-release linux-x64`

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/TechnicallyComputers/MastersOfTerasKasiRecomp.git
```

## Status

Boots far enough to present video/audio. Known bring-up costs: heavy dirty-RAM
interpretation (stuttery audio until more seeds/overlays land). See `ISSUES.md`.
