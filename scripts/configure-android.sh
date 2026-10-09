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
    "--enable-headless-only"
    "--disable-werror"
    "--disable-dtrace"
    "--disable-precompiled-headers"
    "--with-freetype=bundled"
)

if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    # jdk8u autoconf (older autoconf: uses --with-boot-jdk, target via
    # --openjdk-target as well on recent 8u updates).
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --disable-jfr \
        --with-version-opt="eclipse$(date -u +%Y%m%d)"
else
    # JDK 17+ autoconf.
    EXTRA_CFLAGS="--target=${TRIPLE}${ANDROID_API} -fPIC"
    EXTRA_CXXFLAGS="${EXTRA_CFLAGS}"
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --with-extra-cflags="${EXTRA_CFLAGS}" \
        --with-extra-cxxflags="${EXTRA_CXXFLAGS}" \
        --with-version-opt="eclipse$(date -u +%Y%m%d)"
fi

echo "configure finished; build output at ${SRC_DIR}/build"
