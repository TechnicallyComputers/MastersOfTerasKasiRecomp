#!/usr/bin/env bash
# Build MotK on CachyOS/Arch *for* Fedora by compiling inside a Fedora container.
#
# Why: a native CachyOS binary links against glibc 2.43+. Fedora 42 is still
# glibc 2.41 — bundling SDL2 cannot fix that. Build where the target libc lives.
#
# Usage (from MotK repo root, on CachyOS):
#   scripts/build_for_fedora.sh              # Fedora 42 container → bundle zip
#   FEDORA_TAG=41 scripts/build_for_fedora.sh
#   SKIP_BUNDLE=1 scripts/build_for_fedora.sh   # build only
#
# Needs: podman *or* docker, and the usual MotK tree (generated/, submodules).
# Writes: build-fedora/ binary + dist/motk-<VERSION>-linux-fedora<TAG>-bundled.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

FEDORA_TAG="${FEDORA_TAG:-42}"
BUILD_DIR="${BUILD_DIR:-build-fedora}"
SKIP_BUNDLE="${SKIP_BUNDLE:-0}"
IMAGE="docker.io/library/fedora:${FEDORA_TAG}"
JOBS="$(nproc 2>/dev/null || echo 4)"
VERSION="$(tr -d '[:space:]' < VERSION)"

if [[ ! -f generated/SLUS_005.62_dispatch.c ]]; then
  echo "error: generated/ missing — run psxrecomp-game --config game.toml first" >&2
  exit 1
fi
if [[ ! -f psxrecomp/generated/SCPH1001_full.c ]]; then
  echo "error: psxrecomp/generated/SCPH1001_*.c missing (BIOS C for link)" >&2
  exit 1
fi
if [[ ! -f recomp-ui/recomp_ui.cmake ]]; then
  echo "error: recomp-ui submodule missing — git submodule update --init" >&2
  exit 1
fi

if command -v podman >/dev/null 2>&1; then
  CTR=(podman)
elif command -v docker >/dev/null 2>&1; then
  CTR=(docker)
else
  echo "error: need podman or docker to build inside Fedora" >&2
  echo "  CachyOS: sudo pacman -S podman" >&2
  exit 1
fi

echo "Building MotK ${VERSION} inside ${IMAGE} → ${BUILD_DIR}/"
echo "Host is $(. /etc/os-release 2>/dev/null; echo "${NAME:-unknown} ${VERSION_ID:-}") — not used for the link."

# SELinux / rootless: mount repo read-write so cmake can write build-fedora/.
"${CTR[@]}" run --rm \
  --security-opt label=disable \
  -v "${ROOT}:/src:Z" \
  -w /src \
  -e JOBS="${JOBS}" \
  -e VERSION="${VERSION}" \
  -e BUILD_DIR="${BUILD_DIR}" \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    dnf -y install --setopt=install_weak_deps=False \
      gcc gcc-c++ cmake ninja-build pkgconf-pkg-config \
      SDL2-devel mesa-libGL-devel zlib-devel \
      patchelf zip git
    cmake -S . -B "${BUILD_DIR}" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DMOTK_NATIVE=OFF \
      -DRNET_ENABLE_ICE=ON \
      -DPSX_GAME_VERSION="${VERSION}"
    cmake --build "${BUILD_DIR}" --target psx-runtime -j"${JOBS}"
    echo "Container build OK:"
    ldd --version | head -1
    ./'"${BUILD_DIR}"'/Masters_of_Teras_Kasi_Recompiled --help >/dev/null 2>&1 || true
  '

EXE="${BUILD_DIR}/Masters_of_Teras_Kasi_Recompiled"
if [[ ! -f "${EXE}" ]]; then
  echo "error: missing ${EXE} after container build" >&2
  exit 1
fi

MAX_GLIBC="$(
  objdump -T "${EXE}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/^GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
)"
echo "Binary max GLIBC_*: ${MAX_GLIBC:-unknown} (Fedora ${FEDORA_TAG} target)"

if [[ "${SKIP_BUNDLE}" == "1" ]]; then
  echo "SKIP_BUNDLE=1 — not packaging. Run:"
  echo "  scripts/package_linux_bundle.sh ${BUILD_DIR} linux-fedora${FEDORA_TAG}-bundled"
  exit 0
fi

# Bundle using host patchelf/zip if present; otherwise re-enter the container.
if command -v patchelf >/dev/null 2>&1 && command -v zip >/dev/null 2>&1; then
  scripts/package_linux_bundle.sh "${BUILD_DIR}" "linux-fedora${FEDORA_TAG}-bundled"
else
  echo "Host missing patchelf/zip — packaging inside the Fedora container..."
  "${CTR[@]}" run --rm \
    --security-opt label=disable \
    -v "${ROOT}:/src:Z" \
    -w /src \
    -e BUILD_DIR="${BUILD_DIR}" \
    -e FEDORA_TAG="${FEDORA_TAG}" \
    "${IMAGE}" \
    bash -lc '
      set -euo pipefail
      dnf -y install --setopt=install_weak_deps=False patchelf zip >/dev/null
      scripts/package_linux_bundle.sh "${BUILD_DIR}" "linux-fedora${FEDORA_TAG}-bundled"
    '
fi

echo
echo "Copy to the Fedora KDE box:"
echo "  dist/motk-${VERSION}-linux-fedora${FEDORA_TAG}-bundled.zip"
echo "There: unzip && ./run.sh"
echo "If Browse BIOS fails before a dialog: sudo dnf install kdialog"
