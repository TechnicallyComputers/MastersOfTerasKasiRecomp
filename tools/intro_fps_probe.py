#!/usr/bin/env python3
"""Probe MotK intro host FPS via TCP debug (port 4520). Saves incrementally."""
from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from collections import Counter


def cmd(host: str, port: int, payload: dict, timeout: float = 2.0) -> dict:
    s = socket.create_connection((host, port), timeout=timeout)
    s.settimeout(timeout)
    try:
        s.sendall((json.dumps(payload) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(1 << 20)
            if not chunk:
                break
            buf += chunk
        line = buf.split(b"\n", 1)[0]
        return json.loads(line.decode()) if line else {}
    finally:
        s.close()


def wait_port(host: str, port: int, deadline: float) -> None:
    while time.time() < deadline:
        try:
            cmd(host, port, {"cmd": "ping", "id": 1}, timeout=0.5)
            return
        except OSError:
            time.sleep(0.2)
    raise SystemExit(f"debug port {port} not up by deadline")


def top_dirty(dirty: dict, n: int = 12) -> list:
    pcs = dirty.get("per_pc") or []
    pcs = sorted(pcs, key=lambda e: int(e.get("hits", 0)), reverse=True)
    out = []
    for e in pcs[:n]:
        out.append({
            "pc": e.get("pc"),
            "hits": e.get("hits"),
            "insns": e.get("insns"),
        })
    return out


def compact_phase(phase: dict) -> dict:
    if not phase:
        return {}
    keep = {}
    for k in ("ok", "samples", "window_ms", "phases", "shares", "hot_funcs",
              "funcs", "by_phase", "pct"):
        if k in phase:
            keep[k] = phase[k]
    if len(keep) <= 1:
        # unknown schema — keep small scalar/list fields only
        for k, v in phase.items():
            if k in ("id",):
                continue
            if isinstance(v, (int, float, str, bool)) or (
                isinstance(v, list) and len(v) <= 20
            ):
                keep[k] = v
            elif isinstance(v, dict) and len(v) <= 30:
                keep[k] = v
    return keep


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=4520)
    ap.add_argument("--min-fps", type=float, default=50.0)
    ap.add_argument("--interval", type=float, default=0.5)
    ap.add_argument("--max-sec", type=float, default=100.0)
    ap.add_argument("--post-mdec-sec", type=float, default=12.0)
    ap.add_argument("--out", default="/tmp/intro_fps_probe.json")
    args = ap.parse_args()

    wait_port(args.host, args.port, time.time() + 60.0)
    print(f"connected :{args.port}", flush=True)

    t0 = time.time()
    last_t = t0
    last_vb = None
    last_dirty_blocks = None
    last_mdec = 0
    mdec_seen = False
    mdec_idle_since = None
    samples = []
    drops = []
    attrib_snaps = []
    path_counter = Counter()

    def save():
        report = {
            "min_fps": args.min_fps,
            "samples": samples,
            "drops": drops,
            "attrib_snaps": attrib_snaps,
            "path_totals": dict(path_counter),
            "drop_count": len(drops),
            "min_fps_vb": min(
                (s["fps_vb"] for s in samples if s["fps_vb"] is not None),
                default=None,
            ),
        }
        with open(args.out, "w") as f:
            json.dump(report, f)
            f.flush()

    try:
        while True:
            now = time.time()
            elapsed = now - t0
            if elapsed > args.max_sec:
                break
            try:
                vb = cmd(args.host, args.port, {"cmd": "vblank_rate", "id": 2})
                fmv = cmd(args.host, args.port, {"cmd": "fmv_state", "id": 3})
                dirty = cmd(args.host, args.port, {"cmd": "dirty_ram_stats", "id": 4})
            except OSError as e:
                print(f"disconnect: {e}", flush=True)
                break

            delivered = int(vb.get("delivered", 0))
            mdec = int(fmv.get("mdec_decode_count", 0))
            xa = int(fmv.get("xa_stream_active", 0))
            dirty_blocks = int(dirty.get("blocks_run", 0))

            dt = now - last_t
            fps_vb = None
            dirty_dps = None
            if last_vb is not None and dt > 0.05:
                fps_vb = (delivered - last_vb) / dt
                dirty_dps = (dirty_blocks - last_dirty_blocks) / dt

            path_mix = {}
            ring_fps = None
            try:
                ring = cmd(args.host, args.port,
                           {"cmd": "gl_present_ring", "id": 7, "n": 90},
                           timeout=2.0)
                evs = ring.get("events") or []
                local = Counter()
                dts = []
                for i in range(1, len(evs)):
                    local[evs[i][2]] += 1
                    path_counter[evs[i][2]] += 1
                    dts.append(evs[i][3] - evs[i - 1][3])
                path_mix = dict(local)
                pos = [d for d in dts if 0 < d < 200]
                if pos:
                    avg_ms = sum(pos) / len(pos)
                    ring_fps = 1000.0 / avg_ms if avg_ms > 0 else None
            except Exception:
                pass

            sample = {
                "t": round(elapsed, 3),
                "fps_vb": None if fps_vb is None else round(fps_vb, 2),
                "fps_present": None if ring_fps is None else round(ring_fps, 2),
                "mdec": mdec,
                "xa": xa,
                "dirty_blocks_per_s": None if dirty_dps is None else round(dirty_dps, 1),
                "path_mix": path_mix,
                "top_dirty": top_dirty(dirty, 8),
            }

            # Attribute every ~3s during MDEC, and on every drop
            need_attrib = False
            if fps_vb is not None and fps_vb < args.min_fps and (mdec_seen or mdec or xa):
                need_attrib = True
            if mdec > last_mdec and int(elapsed) % 3 == 0:
                need_attrib = True
            if need_attrib:
                try:
                    phase = cmd(args.host, args.port,
                                {"cmd": "phase_profile", "id": 5, "window": 300},
                                timeout=2.5)
                except Exception as e:
                    phase = {"error": str(e)}
                snap = {
                    "t": sample["t"],
                    "fps_vb": sample["fps_vb"],
                    "mdec": mdec,
                    "xa": xa,
                    "dirty_blocks_per_s": sample["dirty_blocks_per_s"],
                    "top_dirty": sample["top_dirty"],
                    "phase": compact_phase(phase),
                }
                attrib_snaps.append(snap)
                sample["phase"] = snap["phase"]

            samples.append(sample)
            flag = (
                fps_vb is not None
                and fps_vb < args.min_fps
                and (mdec_seen or mdec > 0 or xa)
            )
            line = (
                f"t={elapsed:6.1f}s fps_vb={sample['fps_vb']} "
                f"fps_pres={sample['fps_present']} mdec={mdec} xa={xa} "
                f"dirty/s={sample['dirty_blocks_per_s']} paths={path_mix}"
            )
            if flag:
                drops.append(sample)
                top = ",".join(
                    f"{e['pc']}:{e['hits']}" for e in sample["top_dirty"][:4]
                )
                print("DROP  " + line + f" dirty=[{top}]", flush=True)
            else:
                print("ok    " + line, flush=True)

            if mdec > 0:
                mdec_seen = True
                mdec_idle_since = None
            elif mdec_seen and mdec_idle_since is None and xa == 0:
                mdec_idle_since = now
            if (
                mdec_seen
                and mdec_idle_since
                and (now - mdec_idle_since) > args.post_mdec_sec
            ):
                print("mdec idle long enough — stopping", flush=True)
                break

            last_t = now
            last_vb = delivered
            last_dirty_blocks = dirty_blocks
            last_mdec = mdec
            if len(samples) % 4 == 0:
                save()
            time.sleep(args.interval)
    finally:
        try:
            final = {
                "fmv": cmd(args.host, args.port, {"cmd": "fmv_state", "id": 10}),
                "phase": compact_phase(
                    cmd(args.host, args.port,
                        {"cmd": "phase_profile", "id": 11, "window": 500})
                ),
                "dirty_top": top_dirty(
                    cmd(args.host, args.port, {"cmd": "dirty_ram_stats", "id": 12}),
                    20,
                ),
                "gpu": cmd(args.host, args.port, {"cmd": "gpu", "id": 13}),
            }
        except Exception as e:
            final = {"error": str(e)}
        report = {
            "min_fps": args.min_fps,
            "samples": samples,
            "drops": drops,
            "attrib_snaps": attrib_snaps,
            "path_totals": dict(path_counter),
            "final": final,
            "drop_count": len(drops),
            "min_fps_vb": min(
                (s["fps_vb"] for s in samples if s["fps_vb"] is not None),
                default=None,
            ),
        }
        with open(args.out, "w") as f:
            json.dump(report, f, indent=2)
        print(
            f"\nDONE drops={len(drops)} min_fps_vb={report['min_fps_vb']} "
            f"out={args.out}",
            flush=True,
        )
        try:
            cmd(args.host, args.port, {"cmd": "quit", "id": 99}, timeout=0.5)
        except Exception:
            pass
    return 1 if drops else 0


if __name__ == "__main__":
    sys.exit(main())
