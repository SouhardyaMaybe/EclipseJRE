#!/usr/bin/env bash
# Package a built JDK image into the launcher's binpack layout:
#   out/jre-<v>/universal.tar.xz   arch-independent files
#   out/jre-<v>/bin-<arch>.tar.xz  bin/ launchers + arch-specific libs
#   out/jre-<v>/version            opaque stamp read by UnpackJreTask
# DRAFT split rules - validate against launcher extraction order via CI.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

IMAGE_DIR="${IMAGE_DIR:?set IMAGE_DIR to the built JDK image directory}"
RUNTIME_SRC="${IMAGE_DIR}/jre"   # fall back handled below
if [[ ! -d "${RUNTIME_SRC}" ]]; then
    RUNTIME_SRC="${IMAGE_DIR}"
fi

STAGING="${WORKSPACE}/staging"
rm -rf "${STAGING}"
UNIVERSAL_DIR="${STAGING}/universal"
BIN_DIR="${STAGING}/bin-${ECLIPSE_JRE_ARCH}"
mkdir -p "${UNIVERSAL_DIR}" "${BIN_DIR}" "${OUT_DIR}"

# ---------------------------------------------------------------------------
# 1) Universal (arch-independent) files.
#    DRAFT: everything except the ELF bits that live in bin/ and in the
#    arch-specific library directories.
# ---------------------------------------------------------------------------
cp -a "${RUNTIME_SRC}/." "${UNIVERSAL_DIR}/"

# Remove arch-specific pieces from the universal staging dir.
rm -rf "${UNIVERSAL_DIR}/bin"
# Arch-specific lib subdirectories (layout differs per JDK generation:
# lib/jli, lib/server, lib/client, lib/<arch>).
rm -rf "${UNIVERSAL_DIR}/lib/jli" \
       "${UNIVERSAL_DIR}/lib/server" \
       "${UNIVERSAL_DIR}/lib/client" \
       "${UNIVERSAL_DIR}/lib/arm" \
       "${UNIVERSAL_DIR}/lib/aarch64" \
       "${UNIVERSAL_DIR}/lib/aarch32" \
       "${UNIVERSAL_DIR}/lib/x86" \
       "${UNIVERSAL_DIR}/lib/x86_64" \
       "${UNIVERSAL_DIR}/lib/amd64" \
       "${UNIVERSAL_DIR}/lib/i386"
find "${UNIVERSAL_DIR}" -name '*.so' -delete
find "${UNIVERSAL_DIR}" -name '*.so.*' -delete

# ---------------------------------------------------------------------------
# 2) Arch binpack.
# ---------------------------------------------------------------------------
mkdir -p "${BIN_DIR}/bin" "${BIN_DIR}/lib"
cp -a "${RUNTIME_SRC}/bin/." "${BIN_DIR}/bin/"
for dir in jli server client arm aarch64 aarch32 x86 x86_64 amd64 i386; do
    if [[ -d "${RUNTIME_SRC}/lib/${dir}" ]]; then
        cp -a "${RUNTIME_SRC}/lib/${dir}" "${BIN_DIR}/lib/"
    fi
done
# Shared libraries that live directly in lib/ are arch-specific too.
find "${RUNTIME_SRC}/lib" -maxdepth 1 -name '*.so' -exec cp -a {} "${BIN_DIR}/lib/" \;
find "${RUNTIME_SRC}/lib" -maxdepth 1 -name '*.so.*' -exec cp -a {} "${BIN_DIR}/lib/" \;

# ---------------------------------------------------------------------------
# 3) Strip and compress.
# ---------------------------------------------------------------------------
find "${BIN_DIR}" -type f -exec file {} \; | grep ELF | cut -d: -f1 | while read -r elf; do
    "${STRIP}" --strip-unneeded "${elf}" || true
done

xz -T0 -9 -c "${UNIVERSAL_DIR}" > "${OUT_DIR}/universal.tar.xz" &
PID_UNI=$!
(cd "${STAGING}" && tar -c "bin-${ECLIPSE_JRE_ARCH}") | xz -T0 -9 -c > "${OUT_DIR}/bin-${ECLIPSE_JRE_ARCH}.tar.xz"
wait "${PID_UNI}"

# ---------------------------------------------------------------------------
# 4) Version stamp (opaque to the launcher; any changing string works).
# ---------------------------------------------------------------------------
COMMIT="$(git -C "${SRC_DIR}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
printf '%s+%s-%s' "${ECLIPSE_JRE_VERSION}" "${COMMIT}" "$(date -u +%Y%m%d)" > "${OUT_DIR}/version"

echo "packaged:" && ls -la "${OUT_DIR}"
