#!/usr/bin/env bash
# ===========================================================================
# FIRST DRAFT - cross-configure OpenJDK for Android with the NDK toolchain.
# This script is expected to need fixes; validate and iterate via CI runs.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

BOOT_JDK="${BOOT_JDK:?set BOOT_JDK to the boot JDK home for this version}"

cd "${SRC_DIR}"

# Sanity checks: the NDK clang wrappers must exist.
for tool in "${CC}" "${CXX}" "${AR}" "${RANLIB}" "${STRIP}"; do
    if [[ ! -x "${tool}" ]]; then
        echo "missing toolchain component: ${tool}" >&2
        exit 1
    fi
done

COMMON_FLAGS=(
    "--openjdk-target=${OPENJDK_TARGET}"
    "--with-boot-jdk=${BOOT_JDK}"
    "--with-debug-level=release"
    "--with-native-debug-symbols=none"
    "--with-jvm-variants=${JVM_VARIANT}"
    "--with-freetype=bundled"
)

if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    # jdk8u's autoconf predates the 9+ options (--enable-headless-only,
    # --disable-werror, --disable-dtrace, --with-version-opt) and rejects
    # them with "unrecognized options"; this branch only passes options
    # jdk8u understands.
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --disable-jfr \
        --disable-precompiled-headers
else
    # JDK 17+ autoconf.
    EXTRA_CFLAGS="--target=${TRIPLE}${ANDROID_API} -fPIC"
    EXTRA_CXXFLAGS="${EXTRA_CFLAGS}"
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --enable-headless-only \
        --disable-werror \
        --disable-dtrace \
        --disable-precompiled-headers \
        --with-version-opt="eclipse$(date -u +%Y%m%d)" \
        --with-extra-cflags="${EXTRA_CFLAGS}" \
        --with-extra-cxxflags="${EXTRA_CXXFLAGS}"
fi

if [[ ! -d "${SRC_DIR}/build" ]]; then
    echo "configure did not produce ${SRC_DIR}/build - see configure output above" >&2
    exit 1
fi

echo "configure finished; build output at ${SRC_DIR}/build"
