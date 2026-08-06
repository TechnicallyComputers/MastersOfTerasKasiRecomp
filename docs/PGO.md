# MotK PGO (profile-guided optimization)

Authoritative guide (concepts, CMake, when to retrain):

→ **[psxrecomp/docs/PGO.md](../psxrecomp/docs/PGO.md)** (if present in your
psxrecomp checkout)

## Launcher (recommended)

After Generate & rebuild has produced `generated/` once:

1. Settings → **SYSTEM** → **Optimize FMV Playback**
2. Confirm → instrumented rebuild → intro FMV train (video window) →
   `PSX_PGO=use` rebuild → relaunch

Skips the setup wizard; reuses existing generated C. Each peer may run this
independently for rollback (digests must match; binaries need not be
byte-identical). Tunables live in `game.toml` `[pgo]`.

## CLI quick start

```bash
# From MastersOfTerasKasiRecomp root; needs disc under motk/ + BIOS
DISPLAY=:0 ./scripts/pgo_motk_intro.sh
# or: python psxrecomp/psxrecomp_cli.py rebuild --force-pgo --pgo-video …
```

Optional: `PGO_TRAIN_RUNS=3` `PGO_TRAIN_SECS=90`.

Local play after training typically uses:

```bash
cmake -S . -B build-release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DMOTK_NATIVE=ON \
  -DPSX_PGO=use
cmake --build build-release --target psx-runtime -j"$(nproc)"
```

Leave `MOTK_NATIVE=OFF` for portable CI/release packages. See also `ISSUES.md`
(intro FMV host pace).
