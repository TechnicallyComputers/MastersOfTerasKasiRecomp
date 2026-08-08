# Disc identity — Star Wars: Masters of Teras Kasi (USA)

Local-only dump. **Do not commit** the disc image or extracted EXE.

| Field         | Value                                                                                                                   |
| ------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Title         | Star Wars: Masters of Teras Kasi (USA)                                                                                  |
| Serial        | SLUS-00562                                                                                                              |
| Boot EXE      | `SLUS_005.62`                                                                                                           |
| Source path   | `/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA)/Star Wars - Masters of Teras Kasi (USA).cue` |
| Source format | Redump-style multi-track: Track 01 `MODE2/2352` + Tracks 02–17 `AUDIO`                                                  |
| Working tree  | `motk/` — full cue + track bins + extracted `SLUS_005.62` / `SYSTEM.CNF`                                                |

## Boot EXE (from `SYSTEM.CNF` + PS-X EXE header)

| Field                            | Value                  |
| -------------------------------- | ---------------------- |
| `BOOT`                           | `cdrom:\SLUS_005.62;1` |
| Load address                     | `0x80010000`           |
| Entry PC                         | `0x80065A44`           |
| Text size                        | `0x0009B800`           |
| Stack (`SYSTEM.CNF`)             | `0x801FFF00`           |
| Stack (EXE header / `game.toml`) | `0x801FFFF0`           |

## Data track (Track 01) — verify / prepare digests

`game.toml` `[prepare_disc].known_*` hashes this file (first `BINARY` in the cue).

| Field | Value                                                      |
| ----- | ---------------------------------------------------------- |
| Path  | `…/Star Wars - Masters of Teras Kasi (USA) (Track 01).bin` |
| Size  | 108,006,192 bytes (45,921 × 2352)                          |
| MD5   | `8df14d97706048c2b795942783e4cbb2`                         |
| SHA-1 | `b9534175f589690586962f928a9198bfdb7cbb37`                 |

Root directory: `SYSTEM.CNF`, `SLUS_005.62`, `FILE.WFF`, `MOVIE.STR`.

## Full dump

17 track bins + cue under the source directory. All-tracks total ≈ 461,695,248 bytes.
Audio tracks are required for CDDA; do **not** collapse the dump to a single data bin for play.

## Stage into `motk/`

```bash
python3 psxrecomp/tools/prepare_disc.py \
  --config game.toml \
  --project-root . \
  "/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA)/Star Wars - Masters of Teras Kasi (USA).cue"
```

Or the MotK wrapper (same default path):

```bash
python3 tools/prepare_disc.py
```

## Legacy (do not use)

An older workflow converted a 2448-byte/sector ISO-style dump into a single
`motk/*.bin`. That image is harder to identify and drops proper multi-track
CDDA layout. Prefer the Redump cue above.
