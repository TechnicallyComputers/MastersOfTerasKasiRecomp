#!/usr/bin/env bash
# Stage a MotK Linux release zip with bundled non-system shared libraries.
#
# Typical workflow (build host = CachyOS/Arch, test host = Fedora KDE):
#   Do NOT package a native CachyOS binary for Fedora — glibc is newer on
#   CachyOS (e.g. 2.43) than Fedora 42 (2.41). Bundle SDL2 cannot fix that.
#   Build inside Fedora first:
#     scripts/build_for_fedora.sh
#   Or package an already Fedora-linked tree:
#     scripts/package_linux_bundle.sh build-fedora linux-fedora42-bundled
#
# This script only bundles SDL2 / libstdc++ / zlib next to the exe. GL, X11,
# Wayland, and glibc always come from the machine that *runs* the binary.
#
# Usage:
#   scripts/package_linux_bundle.sh <build-dir> [artifact-tag]
# Example:
#   scripts/package_linux_bundle.sh build-fedora linux-fedora42-bundled
#
# Requires: patchelf, zip, ldd  (on CachyOS: pacman -S patchelf zip)
# Optional env:
#   BUNDLE_CXX_RUNTIME=0   skip libstdc++/libgcc_s (default: 1)
#   KEEP_STAGE=1           leave dist/stage-* after zipping
#   MAX_GLIBC_WARN=2.41    warn if binary needs a newer GLIBC_ (Fedora 42)
#
# Writes: dist/motk-<VERSION>-<artifact-tag>.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-}"
ARTIFACT_TAG="${2:-linux-x64-bundled}"
BUNDLE_CXX_RUNTIME="${BUNDLE_CXX_RUNTIME:-1}"
KEEP_STAGE="${KEEP_STAGE:-0}"
# Fedora 42 ships glibc 2.41. Raise if targeting a newer Fedora.
MAX_GLIBC_WARN="${MAX_GLIBC_WARN:-2.41}"

if [[ -z "${BUILD_DIR}" ]]; then
  echo "usage: $0 <build-dir> [artifact-tag]" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "error: this script only packages Linux ELF binaries" >&2
  exit 1
fi

for tool in ldd patchelf zip; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: missing required tool '${tool}'" >&2
    echo "  CachyOS/Arch (build host): sudo pacman -S patchelf zip" >&2
    echo "  Fedora (if packaging there): sudo dnf install patchelf zip" >&2
    exit 1
  fi
done

# Echo the higher of two dotted versions (e.g. 2.43 vs 2.41 → 2.43).
glibc_max() {
  printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

VERSION="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
if [[ -z "${VERSION}" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

BUILD_DIR="$(cd "${BUILD_DIR}" && pwd)"
DIST="${ROOT}/dist"
STAGE="${DIST}/stage-${ARTIFACT_TAG}"
ZIP_NAME="motk-${VERSION}-${ARTIFACT_TAG}.zip"
LIBDIR="${STAGE}/lib"

rm -rf "${STAGE}"
mkdir -p "${STAGE}" "${LIBDIR}" "${DIST}"
rm -f "${DIST}/${ZIP_NAME}"

EXE=""
for cand in \
  "${BUILD_DIR}/Masters_of_Teras_Kasi_Recompiled" \
  "${BUILD_DIR}/psx-runtime"
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

if ! file "${EXE}" | grep -q 'ELF.*executable'; then
  echo "error: ${EXE} is not a Linux ELF executable" >&2
  exit 1
fi

MAX_GLIBC="$(
  objdump -T "${EXE}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/^GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1 || true
)"
if [[ -n "${MAX_GLIBC}" ]]; then
  echo "Binary requires up to GLIBC_${MAX_GLIBC} (Fedora target ceiling GLIBC_${MAX_GLIBC_WARN})"
  if [[ "$(glibc_max "${MAX_GLIBC}" "${MAX_GLIBC_WARN}")" == "${MAX_GLIBC}" \
        && "${MAX_GLIBC}" != "${MAX_GLIBC_WARN}" ]]; then
    echo "error: this binary needs GLIBC_${MAX_GLIBC}, but Fedora (~${MAX_GLIBC_WARN}) is older." >&2
    echo "  Native CachyOS/Arch builds will NOT run on Fedora even with bundled SDL2." >&2
    echo "  From CachyOS, rebuild inside Fedora:" >&2
    echo "    scripts/build_for_fedora.sh" >&2
    echo "  Or force-pack (will fail on Fedora): MAX_GLIBC_WARN=${MAX_GLIBC} $0 ..." >&2
    exit 1
  fi
fi

EXE_BASENAME="$(basename "${EXE}")"
cp -a "${EXE}" "${STAGE}/${EXE_BASENAME}"

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
  if [[ -f "${ROOT}/launcher_assets/img/boxart.tga" ]]; then
    cp -a "${ROOT}/launcher_assets/img/boxart.tga" "${STAGE}/assets/img/boxart.tga"
  else
    echo "error: assets/img/boxart.tga missing (build POST_BUILD or launcher_assets/)" >&2
    exit 1
  fi
fi

cp -a "${ROOT}/game.toml" "${STAGE}/"
cp -a "${ROOT}/VERSION" "${STAGE}/"

# Host libs that must come from the target OS (display stack + glibc).
should_skip_lib() {
  local base="$1"
  case "${base}" in
    linux-vdso.so*|ld-linux*.so*|libc.so*|libm.so*|libdl.so*|librt.so*| \
    libpthread.so*|libresolv.so*|libutil.so*|libanl.so*|libnsl.so*| \
    libGL.so*|libOpenGL.so*|libGLdispatch.so*|libGLX.so*|libEGL.so*| \
    libGLES*.so*|libvulkan.so*| \
    libX11*.so*|libXext*.so*|libXrandr*.so*|libXcursor*.so*|libXi*.so*| \
    libXss*.so*|libXfixes*.so*|libXrender*.so*|libXxf86vm*.so*| \
    libXau.so*|libXdmcp.so*|libxcb*.so*| \
    libwayland*.so*|libxkbcommon*.so*|libdrm.so*|libgbm.so*| \
    libffi.so*|libdbus-1.so*|libsystemd.so*|libudev.so*| \
    libselinux.so*|libpcre*.so*|libcap.so*|libattr.so*|liblzma.so*| \
    libzstd.so*|liblz4.so*|libgpg-error.so*|libgcrypt.so*)
      return 0
      ;;
  esac
  return 1
}

# Paths already considered (absolute), so the dep walk cannot loop.
declare -A SEEN_LIBS=()

# Copy one real library into lib/, preserving the soname symlink name ldd used.
# Prints the absolute path of the staged real file on stdout when newly copied.
# Returns 0 if the lib is present in lib/ (new or existing), 1 on failure.
copy_lib() {
  local src="$1"
  local base dest real staged_real
  if [[ ! -e "${src}" ]]; then
    return 1
  fi
  base="$(basename "${src}")"
  dest="${LIBDIR}/${base}"
  real="$(readlink -f "${src}")"
  if [[ -z "${real}" || ! -f "${real}" ]]; then
    echo "warning: skip unreadable ${src}" >&2
    return 1
  fi
  staged_real="${LIBDIR}/$(basename "${real}")"
  if [[ -e "${dest}" || -e "${staged_real}" ]]; then
    [[ -e "${dest}" ]] || ln -sfn "$(basename "${real}")" "${dest}"
    printf '%s\n' "$(readlink -f "${staged_real}")"
    return 0
  fi
  # Don't preserve ownership (fails in some sandboxes / FAT / non-root).
  cp -L "${real}" "${staged_real}"
  chmod a+rX "${staged_real}"
  if [[ "$(basename "${real}")" != "${base}" ]]; then
    ln -sfn "$(basename "${real}")" "${dest}"
  fi
  echo "  bundled ${base} <- ${real}" >&2
  printf '%s\n' "$(readlink -f "${staged_real}")"
  return 0
}

# Collect dependency closure for an ELF, bundling anything not in the skip list.
collect_deps() {
  local elf="$1"
  local line path base staged
  [[ -n "${elf}" && -e "${elf}" ]] || return 0
  elf="$(readlink -f "${elf}")"
  if [[ -n "${SEEN_LIBS[${elf}]:-}" ]]; then
    return 0
  fi
  SEEN_LIBS["${elf}"]=1

  while IFS= read -r line; do
    path="$(awk '/=>/{print $3; next} /^\t\//{print $1}' <<<"${line}")"
    [[ -n "${path}" && "${path}" != "not" ]] || continue
    [[ -e "${path}" ]] || continue
    base="$(basename "${path}")"
    if should_skip_lib "${base}"; then
      continue
    fi
    if [[ "${BUNDLE_CXX_RUNTIME}" != "1" ]]; then
      case "${base}" in
        libstdc++.so*|libgcc_s.so*) continue ;;
      esac
    fi
    staged="$(copy_lib "${path}" || true)"
    if [[ -n "${staged}" ]]; then
      collect_deps "${staged}"
    fi
  done < <(ldd "${elf}" 2>/dev/null || true)
}

echo "Bundling shared libraries for ${EXE_BASENAME}..."
collect_deps "${STAGE}/${EXE_BASENAME}"

# Always try to pull SDL2 even if ldd somehow omitted a path (broken env).
if ! compgen -G "${LIBDIR}/libSDL2*.so*" >/dev/null; then
  echo "warning: libSDL2 was not bundled — binary may still need system SDL2" >&2
fi

# Prefer bundled libs; keep default loader search as fallback for GL/X11.
patchelf --set-rpath '$ORIGIN/lib' "${STAGE}/${EXE_BASENAME}"
# Bundled libs that dlopen each other (SDL2 internals) also need $ORIGIN.
for so in "${LIBDIR}"/*.so*; do
  [[ -f "${so}" && ! -L "${so}" ]] || continue
  if file "${so}" | grep -q 'ELF.*shared object'; then
    patchelf --set-rpath '$ORIGIN' "${so}" 2>/dev/null || true
  fi
done

echo "Bundled library tree:"
ls -la "${LIBDIR}"

# Smoke-check: with only bundled lib dir, SDL2 / libstdc++ should resolve there.
echo "Loader resolution (LD_LIBRARY_PATH=./lib):"
(
  cd "${STAGE}"
  LD_LIBRARY_PATH="./lib" ldd "./${EXE_BASENAME}" | sed 's/^/  /' || true
)

cat > "${STAGE}/README.txt" <<EOF
Masters of Teras Kasi Recompiled ${VERSION}
Platform pack: ${ARTIFACT_TAG} (Linux, bundled libs)

This build does NOT include a PlayStation BIOS or game disc.
On first launch, select:
  - SCPH1001.BIN (BIOS) — exactly 512 KB
  - Your legally obtained Masters of Teras Kasi disc image (.cue/.bin)

Bundled libraries live in ./lib (SDL2 and, by default, libstdc++/libgcc_s).
OpenGL / Vulkan / X11 / Wayland / glibc come from the host OS.

Built for Fedora (not a native CachyOS/Arch binary). glibc / GL / X11 /
Wayland come from the Fedora machine; SDL2 and friends are in ./lib.

Fedora KDE test box
-------------------
  sudo dnf install mesa-libGL mesa-dri-drivers kdialog

kdialog drives the launcher file picker on KDE. If Browse BIOS crashes
before a dialog appears, install kdialog (or zenity). Or skip the picker:

  ./run.sh --bios /path/to/SCPH1001.BIN --disc /path/to/game.cue

Netplay lobbies match on game title + this VERSION string.
EOF

cat > "${STAGE}/run.sh" <<EOF
#!/usr/bin/env bash
# Optional launcher: keeps cwd next to the binary so assets/ + lib/ resolve.
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
cd "\${HERE}"
export LD_LIBRARY_PATH="\${HERE}/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "\${HERE}/${EXE_BASENAME}" "\$@"
EOF
chmod +x "${STAGE}/run.sh"

(
  cd "${STAGE}"
  # -y: keep lib/*.so soname symlinks (don't duplicate the real .so payload)
  zip -r -y -q "${DIST}/${ZIP_NAME}" .
)

if [[ "${KEEP_STAGE}" != "1" ]]; then
  rm -rf "${STAGE}"
fi

echo "Wrote ${DIST}/${ZIP_NAME}"
echo "Copy that zip to the Fedora KDE box → unzip → ./run.sh"
echo "If file dialogs fail there: sudo dnf install kdialog"
