#!/usr/bin/env bash
# Build/fetch the pinned build dependencies for one build cell:
#
#   all versions  - empty stub archives (libpthread.a, libthread_db.a,
#                   librt.a) so bionic's libc-merged system libraries still
#                   satisfy -l checks during configure and link
#   all versions  - the pinned NDK, installed via sdkmanager if missing
#   all versions  - CUPS 2.2.4 source (headers only; fatal configure check)
#   jdk8          - NDK r10e gcc standalone toolchain (cross compiler)
#   jdk8          - freetype 2.10.4 built per-arch against that toolchain
#                   (jdk8 does not vendor freetype sources; 17+ bundles)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

mkdir -p "${DEPS_DIR}" "${TOOLCHAIN_ROOT}"

# ---------------------------------------------------------------------------
# 1. Pinned NDK: the runner image normally ships it; install only if absent.
# ---------------------------------------------------------------------------
if [[ ! -d "${NDK_ROOT}" ]]; then
    echo "NDK ${ANDROID_NDK_VERSION} missing; installing via sdkmanager"
    sdkmanager "ndk;${ANDROID_NDK_VERSION}"
fi

# ---------------------------------------------------------------------------
# 2. Empty stub archives for libraries bionic folds into libc. Harmless when
#    a real archive exists earlier on the link path; without them configure
#    and the link stage fail on -lpthread / -lthread_db / -lrt.
# ---------------------------------------------------------------------------
if [[ ! -f "${DUMMY_LIBS}/libpthread.a" ]]; then
    mkdir -p "${DUMMY_LIBS}"
    for name in pthread thread_db rt; do
        ar cr "${DUMMY_LIBS}/lib${name}.a"
    done
    echo "created stub archives in ${DUMMY_LIBS}"
fi

# ---------------------------------------------------------------------------
# 3. CUPS 2.2.4 source (all versions): configure's cups header check is fatal
#    in both eras (jdk8 --with-cups-include, JDK 17+ the same); only headers
#    are used, the print pipeline resolves the library at runtime.
# ---------------------------------------------------------------------------
if [[ ! -f "${CUPS_DIR}/cups/cups.h" ]]; then
    echo "fetching cups 2.2.4 source"
    curl -fL --retry 3 -o "${DEPS_DIR}/cups-2.2.4-source.tar.gz" \
        "https://github.com/apple/cups/releases/download/v2.2.4/cups-2.2.4-source.tar.gz"
    tar -xzf "${DEPS_DIR}/cups-2.2.4-source.tar.gz" -C "${DEPS_DIR}"
    rm -f "${DEPS_DIR}/cups-2.2.4-source.tar.gz"
fi

# The remaining dependencies only exist for jdk8 cells.
if [[ "${ECLIPSE_JRE_VERSION}" != "8" ]]; then
    echo "no further dependencies for jdk${ECLIPSE_JRE_VERSION}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 4. Legacy NDK r10e gcc toolchain (standalone, per-arch).
# ---------------------------------------------------------------------------
R10E_ZIP_URL="https://dl.google.com/android/repository/android-ndk-r10e-linux-x86_64.zip"

if [[ ! -x "${TOOLCHAIN}/bin/${R10E_PREFIX}-gcc" ]]; then
    echo "building r10e standalone toolchain for ${ECLIPSE_JRE_ARCH}"
    work="${DEPS_DIR}/r10e-work"
    rm -rf "${work}"
    mkdir -p "${work}"
    curl -fL --retry 3 -o "${work}/ndk-r10e.zip" "${R10E_ZIP_URL}"
    unzip -q "${work}/ndk-r10e.zip" -d "${work}"
    # r10e's helper validates ANDROID_NDK_ROOT/ANDROID_NDK_HOME before it
    # self-locates; the runner exports a stale one, so pin both to the NDK
    # we just extracted.
    ndk_root="${work}/android-ndk-r10e"
    test -d "${ndk_root}"
    ANDROID_NDK_ROOT="${ndk_root}" ANDROID_NDK_HOME="${ndk_root}" \
    bash "${ndk_root}/build/tools/make-standalone-toolchain.sh" \
        --arch="${R10E_ARCH}" \
        --platform="android-${ANDROID_API}" \
        --install-dir="${TOOLCHAIN}"
    rm -rf "${work}"
fi

# Smoke-test the compiler so later steps fail early and clearly.
"${CC}" --version | sed -n '1p'

# ---------------------------------------------------------------------------
# 5. freetype 2.10.4, cross-built per-arch. Host libraries are explicitly
#    disabled so configure can never pick an x86_64 copy by accident.
# ---------------------------------------------------------------------------
FREETYPE_VERSION="2.10.4"
FREETYPE_SRC="${DEPS_DIR}/freetype-${FREETYPE_VERSION}"

if [[ ! -f "${FREETYPE_PREFIX}/lib/libfreetype.so" ]]; then
    if [[ ! -f "${FREETYPE_SRC}/builds/unix/configure" && ! -f "${FREETYPE_SRC}/configure" ]]; then
        echo "fetching freetype ${FREETYPE_VERSION}"
        curl -fL --retry 3 -o "${DEPS_DIR}/freetype.tar.gz" \
            "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" \
            || curl -fL --retry 3 -o "${DEPS_DIR}/freetype.tar.gz" \
                "https://downloads.sourceforge.net/project/freetype/freetype2/${FREETYPE_VERSION}/freetype-${FREETYPE_VERSION}.tar.gz"
        tar -xzf "${DEPS_DIR}/freetype.tar.gz" -C "${DEPS_DIR}"
        rm -f "${DEPS_DIR}/freetype.tar.gz"
    fi

    ft_build="${DEPS_DIR}/freetype-build-${ECLIPSE_JRE_ARCH}"
    rm -rf "${ft_build}"
    mkdir -p "${ft_build}"
    pushd "${ft_build}" > /dev/null
    # The standalone toolchain gcc carries its own bionic sysroot; only PIC
    # needs adding explicitly for shared-library output.
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    CFLAGS="-fPIC" \
    "${FREETYPE_SRC}/configure" \
        --host="${R10E_PREFIX}" \
        --prefix="${FREETYPE_PREFIX}" \
        --enable-shared \
        --disable-static \
        --without-harfbuzz \
        --without-png \
        --without-bzip2 \
        --without-zlib \
        --without-brotli
    make -j"$(nproc)"
    make install
    popd > /dev/null
fi

test -f "${FREETYPE_PREFIX}/lib/libfreetype.so"
echo "dependencies ready for jdk8-${ECLIPSE_JRE_ARCH}"
