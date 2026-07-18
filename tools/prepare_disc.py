#!/usr/bin/env python3
"""Convert a 2448-byte/sector MotK dump to MODE2/2352 .bin/.cue and extract the boot EXE."""

from __future__ import annotations

import argparse
import os
import struct
import sys

SRC_SEC = 2448
DST_SEC = 2352
USER_OFF = 24
USER = 2048

DEFAULT_SRC = (
    "/mnt/crucial4tb/Emulation/roms/ps/Star Wars - Masters of Teras Kasi (USA).iso"
)
BIN_NAME = "Star Wars - Masters of Teras Kasi (USA).bin"
CUE_NAME = "Star Wars - Masters of Teras Kasi (USA).cue"


def read_user_from_src(f, lba: int) -> bytes:
    f.seek(lba * SRC_SEC + USER_OFF)
    return f.read(USER)


def convert_bin(src: str, bin_path: str) -> int:
    n = 0
    with open(src, "rb") as inf, open(bin_path, "wb") as out:
        while True:
            sec = inf.read(SRC_SEC)
            if not sec:
                break
            if len(sec) != SRC_SEC:
                raise SystemExit(f"truncated sector {n}: got {len(sec)} bytes")
            out.write(sec[:DST_SEC])
            n += 1
    return n


def extract_from_bin(bin_path: str, motk_dir: str) -> None:
    with open(bin_path, "rb") as f:
        f.seek(16 * DST_SEC + USER_OFF)
        pvd = f.read(USER)
        if pvd[1:6] != b"CD001":
            raise SystemExit("PVD not found in converted BIN (expected CD001)")
        root_extent = struct.unpack_from("<I", pvd, 158)[0]
        root_size = struct.unpack_from("<I", pvd, 166)[0]
        root = b""
        for i in range((root_size + USER - 1) // USER):
            f.seek((root_extent + i) * DST_SEC + USER_OFF)
            root += f.read(USER)

    entries: dict[str, tuple[int, int]] = {}
    off = 0
    while off < root_size:
        reclen = root[off]
        if reclen == 0:
            off = ((off // USER) + 1) * USER
            if off >= root_size:
                break
            continue
        extent = struct.unpack_from("<I", root, off + 2)[0]
        size = struct.unpack_from("<I", root, off + 10)[0]
        namelen = root[off + 32]
        name = root[off + 33 : off + 33 + namelen]
        if b";" in name:
            name = name.split(b";")[0]
        n = name.decode("ascii", "replace")
        if n not in ("\x00", "\x01"):
            entries[n] = (extent, size)
        off += reclen

    def extract(name: str, out_name: str) -> bytes:
        if name not in entries:
            raise SystemExit(f"missing {name} on disc")
        extent, size = entries[name]
        data = b""
        rem, lba = size, extent
        with open(bin_path, "rb") as bf:
            while rem > 0:
                bf.seek(lba * DST_SEC + USER_OFF)
                s = bf.read(USER)
                take = min(USER, rem)
                data += s[:take]
                rem -= take
                lba += 1
        out_path = os.path.join(motk_dir, out_name)
        with open(out_path, "wb") as out:
            out.write(data)
        print(f"wrote {out_path} ({len(data)} bytes)")
        return data

    extract("SYSTEM.CNF", "SYSTEM.CNF")
    exe = extract("SLUS_005.62", "SLUS_005.62")
    if exe[:8] != b"PS-X EXE":
        raise SystemExit("SLUS_005.62 is not a PS-X EXE")


def write_cue(motk_dir: str) -> None:
    cue_path = os.path.join(motk_dir, CUE_NAME)
    with open(cue_path, "w", encoding="utf-8") as c:
        c.write(f'FILE "{BIN_NAME}" BINARY\n')
        c.write("  TRACK 01 MODE2/2352\n")
        c.write("    INDEX 01 00:00:00\n")
    print(f"wrote {cue_path}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "source",
        nargs="?",
        default=DEFAULT_SRC,
        help="path to the 2448-byte/sector source dump",
    )
    ap.add_argument(
        "--motk-dir",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "motk"
        ),
        help="output directory for bin/cue/EXE (default: <repo>/motk)",
    )
    args = ap.parse_args()

    if not os.path.isfile(args.source):
        print(f"source not found: {args.source}", file=sys.stderr)
        return 1

    os.makedirs(args.motk_dir, exist_ok=True)
    bin_path = os.path.join(args.motk_dir, BIN_NAME)
    n = convert_bin(args.source, bin_path)
    print(f"wrote {bin_path} ({n} sectors, {n * DST_SEC} bytes)")
    write_cue(args.motk_dir)
    extract_from_bin(bin_path, args.motk_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
