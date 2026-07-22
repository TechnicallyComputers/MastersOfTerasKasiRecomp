# MotK PGO (profile-guided optimization)

Authoritative guide (concepts, CMake, when to retrain):

→ **[psxrecomp/docs/PGO.md](../psxrecomp/docs/PGO.md)**

## Quick start (this repo)

```bash
# From MastersOfTerasKasiRecomp root; needs disc under motk/ + BIOS
DISPLAY=:0 ./scripts/pgo_motk_intro.sh
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
