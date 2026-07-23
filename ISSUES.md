# Masters of Teras Kasi — issue log

## Open

### 1. Intro FMV host pace ~40–50 FPS (load-delay path)

With video/audio decoding, Release intro FMV is still host-bound under
faithful load-delay. **LTO-only ≈ ~39 med; MotK intro PGO (`PSX_PGO=use`)
≈ ~48–50 med offline.** `PSX_RUNTIME_PERF_DIAG=1`: guest work ≈920 ms/s
during FMV (present/GL upload not the tax). Keep `build-release` on PGO;
regenerate with `scripts/pgo_motk_intro.sh` after large runtime edits.

**Enhancement (2026-07-22) — rejected for MotK default:** session-scoped
`fmv_load_delay_relax` hits ~450–500 FPS but **intro STR never starts MDEC**
(same class of race as `load_accel.vsync_query`). Keep
`fmv_load_delay_relax = false`; faithful intro ~45–55 FPS is acceptable.
`PSX_FMV_LOAD_DELAY_RELAX=1` remains for A/B only.

**2026-07-21 lever (landed, FPS floor unchanged):** MotK patches
`0x80075F20` (`lui` 0x8007→0x8010); software delay at `0x80075F3C` was
stuck in dirty-RAM interp because exact-range checks covered the whole
function. Runtime now clips ranges at the resume PC and hands
continuations back to compiled (`native_handoffs≈15.8k`, mismatches
~198k→~3.9k; `0x80075F3C` gone from top dirty). FMV-band still ~45 med
— residual is VLC leaves `0x8006A9F8`/`0x8006CBE4` / load-delay volume
(emitter-level charge batching still open).

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

### FMV right-edge junk after rematch (2026-07-19/21) — FIXED (verify)

With 512 RGB width restored, intros are framed correctly. Present never
crops draw width. MotK stays in depth24 across intros; trailing cols are
stale `0x8000` → green/magenta. Policy (landed 2026-07-23): blank beyond
tracked A0 span; **always blank last 8 RGB cols in depth24** (chroma
heuristic removed — it under-fired at the intro→crawl cut); collapse
span only on FB-class A0s (`w >= 256`); on GP1(07h) height change: reset
span + **3 vblank present-hold** (skip Swap, no span update). Rebuild:
`build-release`. Confirm intro→crawl cut (no right-edge flicker).

### FMV host FPS ~45–50 offline (2026-07-21) — known floor

Windowed offline intro settles ~45–50 game FPS with Release+PGO+native.
Headless can hold ~59. This is host MDEC/present cost, not a failed
rebuild — see `docs/PGO.md` / psxrecomp `ISSUES` timing log.

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
