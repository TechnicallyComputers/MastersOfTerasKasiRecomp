#!/usr/bin/env python3
"""Stage the MotK Redump cue/bin set into ``motk/`` (thin wrapper).

Delegates to ``psxrecomp/tools/prepare_disc.py`` with ``game.toml``. Default
source is the multi-track USA Redump cue (see ``DISC.md``).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = (
    "/mnt/crucial4tb/Emulation/roms/ps/"
    "Star Wars - Masters of Teras Kasi (USA)/"
    "Star Wars - Masters of Teras Kasi (USA).cue"
)
FRAMEWORK = ROOT / "psxrecomp" / "tools" / "prepare_disc.py"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "source",
        nargs="?",
        default=DEFAULT_SRC,
        help="path to the Redump .cue (or .bin / .iso)",
    )
    ap.add_argument(
        "--project-root",
        default=str(ROOT),
        help="MotK repo root (default: this repo)",
    )
    ap.add_argument(
        "--config",
        default="",
        help="game.toml (default: <project-root>/game.toml)",
    )
    ap.add_argument(
        "--skip-hash-check",
        action="store_true",
        help="pass through to framework prepare_disc",
    )
    args = ap.parse_args()

    if not FRAMEWORK.is_file():
        print(f"missing framework tool: {FRAMEWORK}", file=sys.stderr)
        return 1

    project_root = Path(args.project_root).expanduser().resolve()
    config = (
        Path(args.config).expanduser().resolve()
        if args.config
        else project_root / "game.toml"
    )
    cmd = [
        sys.executable,
        str(FRAMEWORK),
        "--config",
        str(config),
        "--project-root",
        str(project_root),
        str(Path(args.source).expanduser()),
    ]
    if args.skip_hash_check:
        cmd.append("--skip-hash-check")
    print(" ".join(cmd), flush=True)
    return subprocess.call(cmd, cwd=str(project_root))


if __name__ == "__main__":
    raise SystemExit(main())
