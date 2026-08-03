#!/usr/bin/env bash
# Stage a MotK release zip next to the built runtime.
#
# Ships the redistributable OpenBIOS image this build was compiled against
# (bios/openbios.bin). Does NOT include a game disc or retail SCPH* dumps.
#
# Usage:
#   scripts/package_release.sh <build-dir> <artifact-tag>
# Example:
#   scripts/package_release.sh build-release linux-x64
#
# Writes: dist/motk-<VERSION>-<artifact-tag>.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-}"
ARTIFACT_TAG="${2:-}"

if [[ -z "${BUILD_DIR}" || -z "${ARTIFACT_TAG}" ]]; then
  echo "usage: $0 <build-dir> <artifact-tag>" >&2
  exit 2
fi

VERSION="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
if [[ -z "${VERSION}" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

BUILD_DIR="$(cd "${BUILD_DIR}" && pwd)"
DIST="${ROOT}/dist"
STAGE="${DIST}/stage-${ARTIFACT_TAG}"
ZIP_NAME="motk-${VERSION}-${ARTIFACT_TAG}.zip"

rm -rf "${STAGE}"
mkdir -p "${STAGE}" "${DIST}"
rm -f "${DIST}/${ZIP_NAME}"

# Exe name is derived from WINDOW_TITLE → Masters_of_Teras_Kasi_Recompiled
EXE=""
for cand in \
  "${BUILD_DIR}/Masters_of_Teras_Kasi_Recompiled" \
  "${BUILD_DIR}/Masters_of_Teras_Kasi_Recompiled.exe" \
  "${BUILD_DIR}/Release/Masters_of_Teras_Kasi_Recompiled.exe" \
  "${BUILD_DIR}/psx-runtime" \
  "${BUILD_DIR}/psx-runtime.exe"
do
  if [[ -f "${cand}" ]]; then
    EXE="${cand}"
    break
  fi
done

if [[ -z "${EXE}" ]]; then
  echo "error: runtime executable not found under ${BUILD_DIR}" >&2
  ls -la "${BUILD_DIR}" >&2 || true
  exit 1
fi

cp -a "${EXE}" "${STAGE}/"

# recomp-ui POST_BUILD stages a flat assets/fonts + assets/img next to the exe.
# (Repo source layout is assets/common|consoles/ — do not pack that.)
EXE_DIR="$(dirname "${EXE}")"
if [[ ! -d "${EXE_DIR}/assets/fonts" || ! -d "${EXE_DIR}/assets/img" ]]; then
  echo "error: ${EXE_DIR}/assets/{fonts,img} missing — rebuild psx-runtime" >&2
  exit 1
fi
mkdir -p "${STAGE}/assets"
cp -a "${EXE_DIR}/assets/fonts" "${STAGE}/assets/"
cp -a "${EXE_DIR}/assets/img" "${STAGE}/assets/"

if [[ ! -f "${STAGE}/assets/fonts/LatoLatin-Regular.ttf" ]]; then
  echo "error: assets/fonts incomplete (missing LatoLatin-Regular.ttf)" >&2
  exit 1
fi
if [[ ! -f "${STAGE}/assets/img/boxart.tga" ]]; then
  # MotK boxart is a POST_BUILD overlay; allow packing from the repo tree.
  if [[ -f "${ROOT}/launcher_assets/img/boxart.tga" ]]; then
    cp -a "${ROOT}/launcher_assets/img/boxart.tga" "${STAGE}/assets/img/boxart.tga"
  else
    echo "error: assets/img/boxart.tga missing (build POST_BUILD or launcher_assets/)" >&2
    exit 1
  fi
fi

# Bundled OpenBIOS — required at runtime next to the exe (identity-matched to
# the compiled-in OpenBIOS backend). Prefer POST_BUILD staging beside the
# binary; fall back to the tree copy used as the CMake source.
OPENBIOS_BIN=""
OPENBIOS_LICENSE=""
for cand in \
  "${EXE_DIR}/bios/openbios.bin" \
  "${BUILD_DIR}/bios/openbios.bin" \
  "${ROOT}/psxrecomp/bios/openbios.bin"
do
  if [[ -f "${cand}" ]]; then
    OPENBIOS_BIN="${cand}"
    break
  fi
done
for cand in \
  "${EXE_DIR}/bios/OpenBIOS.LICENSE" \
  "${BUILD_DIR}/bios/OpenBIOS.LICENSE" \
  "${ROOT}/psxrecomp/bios/OpenBIOS.LICENSE"
do
  if [[ -f "${cand}" ]]; then
    OPENBIOS_LICENSE="${cand}"
    break
  fi
done

if [[ -z "${OPENBIOS_BIN}" ]]; then
  echo "error: bios/openbios.bin not found (rebuild psx-runtime to stage it)" >&2
  exit 1
fi

mkdir -p "${STAGE}/bios"
cp -a "${OPENBIOS_BIN}" "${STAGE}/bios/openbios.bin"
if [[ -n "${OPENBIOS_LICENSE}" ]]; then
  cp -a "${OPENBIOS_LICENSE}" "${STAGE}/bios/OpenBIOS.LICENSE"
fi

cp -a "${ROOT}/game.toml" "${STAGE}/"
cp -a "${ROOT}/VERSION" "${STAGE}/"

cat > "${STAGE}/README.txt" <<EOF
Masters of Teras Kasi Recompiled ${VERSION}
Platform pack: ${ARTIFACT_TAG}

BIOS
  This build ships OpenBIOS (bios/openbios.bin) — leave the launcher BIOS
  setting on "Bundled BIOS". Retail dumps (e.g. SCPH1001.BIN) are NOT
  accepted unless the binary was compiled from that exact image.

Game disc
  On first launch, select your legally obtained Masters of Teras Kasi
  disc image (.cue/.bin). The disc is not included in this zip.

Netplay lobbies match on game title + this VERSION string.
EOF

(
  cd "${STAGE}"
  if command -v zip >/dev/null 2>&1; then
    zip -r -q "${DIST}/${ZIP_NAME}" .
  else
    # Fallback (macOS / minimal images): tar.gz with .zip name avoided —
    # prefer real zip. Install zip in CI.
    echo "error: zip not found; install zip to package releases" >&2
    exit 1
  fi
)

rm -rf "${STAGE}"
echo "Wrote ${DIST}/${ZIP_NAME}"
