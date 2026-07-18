# Masters of Teras Kasi — issue log

Scaffold created 2026-07-18. No runtime bring-up issues filed yet.

## Known local notes

1. **Source dump is 2448 B/sector** (raw + subchannel). PSXRecomp expects
   MODE2/2352 or cooked 2048. Use `tools/prepare_disc.py` to strip subchannel
   into `motk/*.bin` + `.cue`.
2. **Seeds are JAL-only auto-scan** (`seeds/ghidra_funcs.txt`). Indirect
   dispatch / overlays will need Ghidra or runtime discovery follow-up.
3. **Framework pin** is whatever `psxrecomp` submodule HEAD was at scaffold
   time. For delay-sync / `recomp-net` work, point or update the submodule at
   a local `psxrecomp` checkout that already vendors `lib/recomp-net`.
