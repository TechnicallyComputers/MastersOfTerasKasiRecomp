# Masters of Teras Kasi — issue log

## Open

### 1. Intro FMV host pace ~40–50 FPS (load-delay path)

With video/audio decoding, Release intro FMV is still host-bound under
faithful load-delay. **LTO-only ≈ ~39 med; MotK intro PGO (`PSX_PGO=use`)
≈ ~50 med offline.** Keep `build-release` on PGO; regenerate with
`scripts/pgo_motk_intro.sh` after large runtime edits. Title/char-select
starfield path is fixed (below). Remaining FMV cost is VLC
`0x8006A9F8`/`0x8006CBE4` + load-delay.

**Netplay (2026-07-21):** Same-machine FMV ~30–40 was the rematch-safe
`finish→admit→pace→present` order (depth24 CPU present after admit), not
lockstep itself (gameplay stays ~60). Restored early-build
`finish→present→admit/pace` plus half-rate depth24 present skip. Rebuild
`build-release`; verify intro FPS + tick-0 arm. Barrier still UDP
`poll()`; pin localhost peers to disjoint CPU halves. Offline full speed.

**Netplay saves (2026-07-20):** Host owns save/load + memcard sync.
Guest writes only `saves/netplay/`. Flow: local save (both) → hash probe →
skip transfer on match, else host→guest chunked blob + CRC verify; load
and match-start memcards use the same pattern. Guest F1–F12 ignored.
Post-load resume: ready rendezvous → one `hard_resync`+prime (clears
remotes) at mutual ready → both stay in LOAD_READY until `try_admit`
succeeds; frontend restage; FPS suppressed during barrier.

`PSX_LOAD_DELAY=0` still goes to hundreds of FPS (timing wrong; proves
remaining host cost). **Do not** re-enable MotK `load_accel.vsync_query`
or raise `PSX_DEADLINE_HARD_CAP` / in-exception VBlank chunking without
checking `mdec_decode_count` / XA — those “60 FPS” wins raced guest time
with **no MDEC**.

## Fixed / reverted

### Title screen rainbow/static after FMV (2026-07-20) — FIXED (verify)

Leave depth24 restaged full CPU VRAM into the GL/VK FBO as 1555 while
CPU still held packed RGB888 from MDEC → noisy black + rainbow strip;
“Press Start”/copyright still drew as prims. V2: skip only
framebuffer-sized depth24 A0s (keep texture uploads); on leave
scissor-clear the skipped FB union (no RGB888-as-1555 restage).
Rebuild: `build-release` + `PSX_PGO=use`. Confirm title after intros.

### Char-select shrink to left-center (2026-07-20) — OPEN

After FMV, char-select shrink/spin aims left-of-center. Probe: menus
run 512×240 (hres1=2), GTE OFX=256 / OFY=120 (correct for 512). In-game
OK. May be separate from title VRAM coherency — needs user A/B vs
DuckStation/Beetle on the shrink pivot.

### Title / char-select ~8–10 FPS (2026-07-19) — FIXED

Two stacked bugs:

1. **Savestate PC wipe:** `boot_state_load` forced `cpu->pc = entry_pc`, so
   Shift+F1 loads resumed at `0x80065A44` with menu RAM/GPU → display stuck
   off. False ~60 FPS in agent tests. Fix: restore saved `c->pc`.
2. **Starfield GL cost:** live char select issues ~30k/s GP0(68h) 1×1 dots
   (`gpu_share` ~0.8). Each dot was two immediate GL triangles (BufferData +
   DrawArrays). Flat GEO batching in `gpu_gl_renderer.c` → locked ~60 FPS;
   `gpu_share` ~0.06. Draw-area reject (empty OT) still helps inter-movie gaps.

### Crawl FMV framing (2026-07-18) — FIXED

Two layered bugs:

1. **Width:** Present width follows GP1(06h)÷dot-clock for both 15- and
   24-bit (MotK CRTC → 512 RGB). A blanket `(W*2)/3` (512→341) left-shifts
   the frame and clips the right of the video — reconfirmed 2026-07-19;
   do not reapply. Earlier wrap/shear was from reverted MDEC/DMA experiments.
2. **Aspect:** GP1(07h) height 128 was stretched to full 4:3 (~2× vertical
   scale → looked too wide / right-clipped in the window). Present letterboxes
   short bands (`src_h/240`) inside the 4:3 rect (GL/SDL/VK).

CD-only `spu_render` kept. Intro host FPS still ~40–50 under load-delay.

### FMV right-edge junk after rematch (2026-07-19/20) — FIXED (verify)

With 512 RGB width restored, intros are framed correctly. Present never
crops draw width (that caused a flickering black pillar). Trailing junk
is black-filled in-buffer when chroma is *dense* in the last ~8 cols —
not column-replicated (replication smeared the 2nd intro starfield into
a flickering stretch). Rebuild: `build-release` with `PSX_PGO=use`.
Confirm 2nd intro right edge stays clean.

### Fake 60 FPS / no video (2026-07-18)

A/B proved:

| Config | MDEC/XA |
|--------|---------|
| `load_accel.vsync_query` on | mdec stays 0, display dead |
| `event_horizon_any` / drive-reading horizon | races past movie |
| `HARD_CAP` 16k→564480 | mdec stays 0 |
| in-exception VBlank chunking | mdec stays 0 |
| VSync HLE off + HARD_CAP 16k | mdec/XA run |

`game.toml` keeps `load_accel` **disabled**. Framework keeps sticky-CD /
load-delay coalesce / MDEC DMA bulk + IDCT skips; MotK must not use VSync
HLE until it is validated against real FMV decode.

### Window close SIGABRT
`shutdown_runtime_and_exit` + `std::_Exit`.

## Notes

1. Prefer Release for playtesting; RelWithDebInfo + `fmv_state` to confirm
   `mdec_decode_count` increases during the logo/crawl.
2. Source dump must be 2448 B/sector (`tools/prepare_disc.py`).
