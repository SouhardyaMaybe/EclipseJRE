#!/usr/bin/env bash
# ===========================================================================
# Package a built JDK image into the launcher's binpack layout:
#   out/jre-<v>/universal.tar.xz   arch-independent files
#   out/jre-<v>/bin-<arch>.tar.xz  bin/ launchers + arch-specific libs
#   out/jre-<v>/version            opaque stamp read by UnpackJreTask
#
# Split rules follow the layout the launcher consumes:
#   - universal keeps classes/config/legal/resources and jspawnhelper, and
#     drops every ELF: bin/, lib/<arch>/, lib/{jli,server,client}/, *.so*,
#     lib/jexec, release
#   - bin-<arch> carries bin/*, the arch lib dirs, top-level *.so, jexec and
#     release (release holds OS_ARCH, which the launcher maps to the runtime
#     architecture)
#
# jdk8 needs no extra work (the legacy build emits a j2re-image directly);
# jdk17+ runtimes are jlinked from the built android image with a host jlink
# of the same feature release, using the pinned module list under
# scripts/modules/<version>.modules, then release is rewritten from the
# target image so OS_ARCH stays the Android one.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

IMAGE_DIR="${IMAGE_DIR:?set IMAGE_DIR to the built JDK image directory}"
test -f "${IMAGE_DIR}/release"

STAGING="${WORKSPACE}/staging"
rm -rf "${STAGING}"
UNIVERSAL_DIR="${STAGING}/universal"
BIN_DIR="${STAGING}/bin-${ECLIPSE_JRE_ARCH}"
mkdir -p "${UNIVERSAL_DIR}/lib" "${BIN_DIR}/bin" "${BIN_DIR}/lib" "${OUT_DIR}"

# ---------------------------------------------------------------------------
# 1) Resolve the runtime source: the jdk8 j2re-image as-is, or a jlinked
#    runtime for 17+.
# ---------------------------------------------------------------------------
RUNTIME_SRC="${IMAGE_DIR}"
if [[ "${ECLIPSE_JRE_VERSION}" != "8" ]]; then
    MODULES="$(tr '\n' ' ' < "${SCRIPT_DIR}/modules/${ECLIPSE_JRE_VERSION}.modules" | xargs)"
    test -n "${MODULES}"
    JLINK_HOME="${JLINK_HOME:?set JLINK_HOME to a host JDK of the same feature release}"
    RUNTIME_SRC="${STAGING}/runtime"
    echo "jlinking runtime with ${ECLIPSE_JRE_VERSION}.modules"
    "${JLINK_HOME}/bin/jlink" \
        --module-path "${IMAGE_DIR}/jmods" \
        --add-modules "${MODULES}" \
        --output "${RUNTIME_SRC}"

    # jlink stamps its *host* properties; rebuild release from the target
    # image (OS_ARCH/OS_NAME/JAVA_VERSION of the Android build) plus the
    # module list actually linked.
    grep -v '^MODULES=' "${IMAGE_DIR}/release" > "${RUNTIME_SRC}/release"
    printf 'MODULES="%s"\n' "${MODULES}" >> "${RUNTIME_SRC}/release"
fi

test -d "${RUNTIME_SRC}/bin"

# ---------------------------------------------------------------------------
# 2) Universal (arch-independent) staging.
# ---------------------------------------------------------------------------
cp -a "${RUNTIME_SRC}/." "${UNIVERSAL_DIR}/"

rm -rf "${UNIVERSAL_DIR}/bin"
# Arch-specific lib subdirectories (layout differs per JDK generation:
# lib/jli, lib/server, lib/client, lib/<legacy arch>).
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
# release and jexec are arch-bound: release carries OS_ARCH, jexec is an
# arch ELF - both belong on the bin side.
rm -f "${UNIVERSAL_DIR}/release" "${UNIVERSAL_DIR}/lib/jexec"
# ---------------------------------------------------------------------------
# 3) Arch binpack.
# ---------------------------------------------------------------------------
cp -a "${RUNTIME_SRC}/bin/." "${BIN_DIR}/bin/"
for dir in jli server client arm aarch64 aarch32 x86 x86_64 amd64 i386; do
    if [[ -d "${RUNTIME_SRC}/lib/${dir}" ]]; then
        cp -a "${RUNTIME_SRC}/lib/${dir}" "${BIN_DIR}/lib/"
    fi
done
# Shared libraries that live directly in lib/ are arch-specific too.
find "${RUNTIME_SRC}/lib" -maxdepth 1 -name '*.so' -exec cp -a {} "${BIN_DIR}/lib/" \;
find "${RUNTIME_SRC}/lib" -maxdepth 1 -name '*.so.*' -exec cp -a {} "${BIN_DIR}/lib/" \;
if [[ -f "${RUNTIME_SRC}/release" ]]; then
    cp -a "${RUNTIME_SRC}/release" "${BIN_DIR}/release"
fi
if [[ -f "${RUNTIME_SRC}/lib/jexec" ]]; then
    cp -a "${RUNTIME_SRC}/lib/jexec" "${BIN_DIR}/lib/jexec"
fi

# jdk8 safety net: the image must end up with libfreetype.so next to the
# VM (fontmanager links it); if the legacy copy rule did not place it,
# take the per-arch copy produced by prepare-deps.sh.
if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    FT_HIT="$(find "${BIN_DIR}" -name 'libfreetype.so*' -print -quit)"
    if [[ -z "${FT_HIT}" ]]; then
        JVM_CFG="$(find "${BIN_DIR}" -name jvm.cfg -print -quit)"
        if [[ -n "${JVM_CFG}" && -f "${FREETYPE_PREFIX}/lib/libfreetype.so" ]]; then
            cp -L "${FREETYPE_PREFIX}/lib/libfreetype.so" "$(dirname "${JVM_CFG}")/"
            echo "staged freetype next to $(dirname "${JVM_CFG}")"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 4) Strip and compress.
# ---------------------------------------------------------------------------
find "${BIN_DIR}" -type f -exec file {} \; | grep ELF | cut -d: -f1 | while read -r elf; do
    "${STRIP}" --strip-unneeded "${elf}" || true
done

xz -T0 -9 -c "${UNIVERSAL_DIR}" > "${OUT_DIR}/universal.tar.xz" &
PID_UNI=$!
(cd "${STAGING}" && tar -c "bin-${ECLIPSE_JRE_ARCH}") | xz -T0 -9 -c > "${OUT_DIR}/bin-${ECLIPSE_JRE_ARCH}.tar.xz"
wait "${PID_UNI}"

# ---------------------------------------------------------------------------
# 5) Version stamp (opaque to the launcher; any changing string works).
# ---------------------------------------------------------------------------
COMMIT="$(git -C "${SRC_DIR}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
printf '%s+%s-%s' "${ECLIPSE_JRE_VERSION}" "${COMMIT}" "$(date -u +%Y%m%d)" > "${OUT_DIR}/version"

echo "packaged:" && ls -la "${OUT_DIR}"
