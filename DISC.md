# Disc identity — Star Wars: Masters of Teras Kasi (USA)

Local-only dump. **Do not commit** the disc image or extracted EXE.

| Field | Value |
|-------|-------|
| Title | Star Wars: Masters of Teras Kasi (USA) |
| Serial | SLUS-00562 |
| Boot EXE | `SLUS_005.62` |
| Source path | `/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA).iso` |
| Source format | Raw CD with subchannel (2448-byte sectors) |
| Working format | `motk/*.bin` + `motk/*.cue` — MODE2/2352 (subchannel stripped) |

## Boot EXE (from `SYSTEM.CNF` + PS-X EXE header)

| Field | Value |
|-------|-------|
| `BOOT` | `cdrom:\SLUS_005.62;1` |
| Load address | `0x80010000` |
| Entry PC | `0x80065A44` |
| Text size | `0x0009B800` |
| Stack (`SYSTEM.CNF`) | `0x801FFF00` |
| Stack (EXE header / `game.toml`) | `0x801FFFF0` |

## Local working image (2352)

Produced by stripping the trailing 96-byte subchannel from each source sector.

| Field | Value |
|-------|-------|
| Path | `motk/Star Wars - Masters of Teras Kasi (USA).bin` |
| Size | 461,772,864 bytes (196,332 × 2352) |
| MD5 | `d3b3d3aaa70b6f98983bafeb8daf24a1` |
| SHA-1 | `2ada1f21012660b5eb2eb1dc752cdfcfb253ff8a` |

## Source image (2448, as found)

| Field | Value |
|-------|-------|
| Size | 480,620,736 bytes (196,332 × 2448) |
| MD5 | `6b6e11e4ae456d4e307d8e541e26decd` |
| SHA-1 | `deabb6b39e8857cdbbaacbd72cb0e26646183a63` |

Root directory also contains `FILE.WFF` and `MOVIE.STR` (not needed for initial recomp bring-up).

## Recreate `motk/` from the source ISO

```bash
python3 tools/prepare_disc.py \
  "/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA).iso"
```
