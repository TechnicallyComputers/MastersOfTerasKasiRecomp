#!/usr/bin/env bash
# Reproduce / capture the Browse-BIOS SIGSEGV under gdb.
#
# The MotK Release binary is LTO'd, so symbols become e.g.
#   launcher_pick_file.constprop.0
#   tinyfd_openFileDialog.constprop.0
# Plain `break launcher_pick_file` stays pending forever. This script uses
# `rbreak` and also breaks on SIGSEGV, then dumps bt / bt full.
#
# Usage (from MotK repo root, or pass an absolute exe path):
#   scripts/debug_bios_browse_crash.sh
#   scripts/debug_bios_browse_crash.sh ./dist/motk-0.1.0-linux-x64/Masters_of_Teras_Kasi_Recompiled
#   scripts/debug_bios_browse_crash.sh ./build-release/Masters_of_Teras_Kasi_Recompiled
#
# When the game window appears: click "Browse BIOS" in the first-run setup
# modal (do not pick a file yet — the known crash is before the dialog).
# On stop, gdb prints the backtrace and writes:
#   dist/debug-bios-browse-crash-<timestamp>.log
#
# Env:
#   GDB=gdb                 gdb binary
#   EXTRA_ARGS='--bios …'   forwarded to the game after the exe path
#   AUTO_QUIT=1             quit gdb after first stop (default: leave you in gdb)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GDB="${GDB:-gdb}"
AUTO_QUIT="${AUTO_QUIT:-0}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${ROOT}/dist"
LOG="${LOG_DIR}/debug-bios-browse-crash-${STAMP}.log"
GDB_CMDS="$(mktemp "${TMPDIR:-/tmp}/motk-gdb-bios.XXXXXX.gdb")"

cleanup() { rm -f "${GDB_CMDS}"; }
trap cleanup EXIT

if ! command -v "${GDB}" >/dev/null 2>&1; then
  echo "error: gdb not found (install gdb)" >&2
  exit 1
fi

resolve_exe() {
  local cand
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    cand="$1"
    if [[ ! -f "${cand}" ]]; then
      echo "error: executable not found: ${cand}" >&2
      exit 1
    fi
    printf '%s\n' "$(cd "$(dirname "${cand}")" && pwd)/$(basename "${cand}")"
    return
  fi
  for cand in \
    "${ROOT}/build-dbg/Masters_of_Teras_Kasi_Recompiled" \
    "${ROOT}/build-release/Masters_of_Teras_Kasi_Recompiled" \
    "${ROOT}/build-fedora/Masters_of_Teras_Kasi_Recompiled" \
    "${ROOT}/build/Masters_of_Teras_Kasi_Recompiled"
  do
    if [[ -f "${cand}" ]]; then
      printf '%s\n' "${cand}"
      return
    fi
  done
  # Newest packaged linux zip extract under dist/
  local found
  found="$(find "${ROOT}/dist" -maxdepth 3 -type f -name 'Masters_of_Teras_Kasi_Recompiled' 2>/dev/null \
    | head -1 || true)"
  if [[ -n "${found}" ]]; then
    printf '%s\n' "${found}"
    return
  fi
  echo "error: no Masters_of_Teras_Kasi_Recompiled found." >&2
  echo "  Pass a path, or build first:" >&2
  echo "    cmake -S . -B build-dbg -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DMOTK_NATIVE=OFF" >&2
  echo "    cmake --build build-dbg --target psx-runtime -j\"\$(nproc)\"" >&2
  exit 1
}

EXE="$(resolve_exe "${1:-}")"
shift $(( $# > 0 ? 1 : 0 )) || true
# Remaining args + EXTRA_ARGS go to the game.
GAME_ARGS=( "$@" )
if [[ -n "${EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  GAME_ARGS+=( ${EXTRA_ARGS} )
fi

EXE_DIR="$(dirname "${EXE}")"
mkdir -p "${LOG_DIR}"

# Prefer RelWithDebInfo hint when the chosen binary looks like a stripped Release.
if ! nm -C "${EXE}" 2>/dev/null | grep -q 'launcher_pick_file'; then
  echo "note: '${EXE}' has no launcher_pick_file symbol in nm (heavy LTO/strip)."
  echo "      Prefer build-dbg (RelWithDebInfo) for clearer frames."
fi

cat > "${GDB_CMDS}" <<EOF
set pagination off
set confirm off
set debuginfod enabled on
set print pretty on
set logging file ${LOG}
set logging overwrite on
set logging enabled on

# LTO may rename to *.constprop.0 — rbreak matches both.
rbreak ^launcher_pick_file
rbreak ^tinyfd_openFileDialog

# Always catch the known fault class.
catch signal SIGSEGV

printf "\\n=== MotK Browse-BIOS crash capture ===\\n"
printf "exe: %s\\n", "${EXE}"
printf "cwd: %s\\n", "${EXE_DIR}"
printf "log: %s\\n", "${LOG}"
printf "\\nWhen the window appears, click Browse BIOS in First-run setup.\\n"
printf "(Do not select a file — crash is before the native dialog.)\\n\\n"

# gdb's `cd` treats quotes as part of the path — do not quote here.
cd ${EXE_DIR}
# Inferior argv comes from gdb --args below.
run

printf "\\n=== STOPPED ===\\n"
info program
printf "\\n--- bt ---\\n"
bt
printf "\\n--- bt full ---\\n"
bt full
printf "\\n--- threads ---\\n"
info threads
printf "\\n--- registers ---\\n"
info registers
printf "\\n--- disasm around pc ---\\n"
x/24i \$pc-32

set logging enabled off
printf "\\nWrote %s\\n", "${LOG}"
printf "\\nIf this is launcher_pick_file / tinyfd entry (not SIGSEGV): type  continue\\n"
printf "then  bt  again after the next stop.\\n"
EOF

if [[ "${AUTO_QUIT}" == "1" ]]; then
  cat >> "${GDB_CMDS}" <<'EOF'
quit
EOF
else
  cat >> "${GDB_CMDS}" <<'EOF'
printf "\nLeaving you in gdb. Useful:  continue   bt   quit\n"
EOF
fi

echo "Launching gdb on:"
echo "  ${EXE}"
echo "Working directory (assets/ next to exe):"
echo "  ${EXE_DIR}"
echo "Log will be written to:"
echo "  ${LOG}"
echo
echo ">>> Click Browse BIOS when the first-run modal appears <<<"
echo

# Run from repo root; gdb 'cd' switches to exe dir before run.
cd "${ROOT}"
exec "${GDB}" -q -x "${GDB_CMDS}" --args "${EXE}" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"}
