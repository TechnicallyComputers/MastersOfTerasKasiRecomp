#!/usr/bin/env bash
# MotK thin wrapper around the shared psxrecomp setup-host packager.
#
# Usage:
#   scripts/package_setup_release.sh <build-dir> <artifact-tag> [recompiler-build-dir]
#
# Writes: dist/motk-<VERSION>-<artifact-tag>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-}"
ARTIFACT_TAG="${2:-}"
RECOMPILER_BUILD="${3:-build-recompiler}"

if [[ -z "${BUILD_DIR}" || -z "${ARTIFACT_TAG}" ]]; then
  echo "usage: $0 <build-dir> <artifact-tag> [recompiler-build-dir]" >&2
  exit 2
fi

PACKAGER="${ROOT}/psxrecomp/tools/package_setup_host.sh"
if [[ ! -f "${PACKAGER}" ]]; then
  echo "error: missing ${PACKAGER} (psxrecomp submodule)" >&2
  exit 1
fi
chmod +x "${PACKAGER}" 2>/dev/null || true

cd "${ROOT}"
exec bash "${PACKAGER}" \
  --root "${ROOT}" \
  --build-dir "${BUILD_DIR}" \
  --artifact "${ARTIFACT_TAG}" \
  --zip-prefix motk \
  --exe-name Masters_of_Teras_Kasi_Recompiled \
  --display-name "Masters of Teras Kasi Recompiled" \
  --recompiler-build "${RECOMPILER_BUILD}" \
  --version-env RELEASE_VERSION \
  --disc-hint "your legally owned Masters of Teras Kasi (USA) disc" \
  --project-file CMakeLists.txt \
  --project-file game.toml \
  --project-file VERSION \
  --project-file codegen_setup.c \
  --project-file codegen_setup.h \
  --project-file README.md \
  --project-dir seeds \
  --project-dir launcher_assets
