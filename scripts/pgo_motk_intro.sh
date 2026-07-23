#!/usr/bin/env bash
# MotK intro PGO: instrument → multi-run train (logo+crawl) → rebuild with profiles.
# Usage: from repo root, DISPLAY=:0 ./scripts/pgo_motk_intro.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build-release"
DISC='motk/Star Wars - Masters of Teras Kasi (USA).cue'
TRAIN_SECS="${PGO_TRAIN_SECS:-90}"
TRAIN_RUNS="${PGO_TRAIN_RUNS:-3}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/xauth_dvexyE}"

cd "$BUILD"
cmake .. -DCMAKE_BUILD_TYPE=Release -DPSX_PGO=generate
ninja Masters_of_Teras_Kasi_Recompiled

pgrep -x Masters_of_Tera | xargs -r kill || true
# Keep existing .gcda across runs so profiles merge (wipe only on fresh generate).
rm -rf "$BUILD/pgo"
mkdir -p "$BUILD/pgo"

cd "$ROOT"
for run in $(seq 1 "$TRAIN_RUNS"); do
  echo "PGO train run $run/$TRAIN_RUNS (${TRAIN_SECS}s)..."
  ./build-release/Masters_of_Teras_Kasi_Recompiled \
    --no-launcher --game game.toml --disc "$DISC" \
    >/tmp/motk_pgo_train_${run}.log 2>&1 &
  MPID=$!
  sleep "$TRAIN_SECS"
  # Soft-stop so atexit/__gcov_exit flushes .gcda (default SIGTERM does not).
  if kill -0 "$MPID" 2>/dev/null; then
    kill -TERM "$MPID" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$MPID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$MPID" 2>/dev/null || true
  fi
  wait "$MPID" 2>/dev/null || true
done

n_gcda=$(find "$BUILD" -name '*.gcda' 2>/dev/null | wc -l)
echo "PGO profiles: $n_gcda .gcda under $BUILD"
if [[ "$n_gcda" -lt 1 ]]; then
  echo "ERROR: no profiles written" >&2
  exit 1
fi

cd "$BUILD"
cmake .. -DCMAKE_BUILD_TYPE=Release -DPSX_PGO=use
ninja Masters_of_Teras_Kasi_Recompiled
echo "PGO use build ready: $BUILD/Masters_of_Teras_Kasi_Recompiled"
