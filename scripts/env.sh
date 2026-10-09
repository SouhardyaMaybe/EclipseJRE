#!/usr/bin/env bash
# Shared environment for the Eclipse JRE pipeline.
#
# Resolves, for one (version, arch) build cell:
#   - the target triple and OpenJDK's --openjdk-target value
#   - the cross toolchain: legacy NDK gcc (r10e standalone) for jdk8,
#     NDK LLVM clang for jdk17+
#   - the JVM variant: client on 32-bit jdk8, server everywhere else
#   - pinned dependency locations (cups, freetype, dummy archives)
#
# Every variable is overridable from the environment for local runs.

set -euo pipefail

# The runner image ships this NDK preinstalled; prepare-deps.sh installs it
# via sdkmanager only if the directory is missing.
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-27.3.13750724}"
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
NDK_ROOT="${NDK_ROOT:-${ANDROID_SDK}/ndk/${ANDROID_NDK_VERSION}}"
ANDROID_API="${ANDROID_API:-21}"

ECLIPSE_JRE_VERSION="${ECLIPSE_JRE_VERSION:?set ECLIPSE_JRE_VERSION to 8, 17, 21 or 25}"
ECLIPSE_JRE_ARCH="${ECLIPSE_JRE_ARCH:?set ECLIPSE_JRE_ARCH to arm, arm64, x86 or x86_64}"

case "${ECLIPSE_JRE_ARCH}" in
    arm)
        TRIPLE="arm-linux-android"
        # clang's arm32 Android wrapper prefix differs from the binutils one
        R10E_ARCH="arm"
        R10E_PREFIX="arm-linux-androideabi"
        ;;
    arm64)
        TRIPLE="aarch64-linux-android"
        R10E_ARCH="arm64"
        R10E_PREFIX="aarch64-linux-android"
        ;;
    x86)
        TRIPLE="i686-linux-android"
        R10E_ARCH="x86"
        R10E_PREFIX="i686-linux-android"
        ;;
    x86_64)
        TRIPLE="x86_64-linux-android"
        R10E_ARCH="x86_64"
        R10E_PREFIX="x86_64-linux-android"
        ;;
    *)
        echo "unknown arch: ${ECLIPSE_JRE_ARCH}" >&2
        exit 1
        ;;
esac
OPENJDK_TARGET="${TRIPLE}"
# NDK clang target-prefix wrappers: arm32 uses armv7a-linux-androideabi, all
# other arches share the binutils triple.
if [[ "${ECLIPSE_JRE_ARCH}" == "arm" ]]; then
    CLANG_PREFIX="armv7a-linux-androideabi"
else
    CLANG_PREFIX="${TRIPLE}"
fi

WORKSPACE="${WORKSPACE:-${GITHUB_WORKSPACE:-$(pwd)}}"
SRC_DIR="${SRC_DIR:-${WORKSPACE}/openjdk-src}"
OUT_DIR="${OUT_DIR:-${WORKSPACE}/out/jre-${ECLIPSE_JRE_VERSION}}"
DEPS_DIR="${DEPS_DIR:-${WORKSPACE}/deps}"
TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-${WORKSPACE}/toolchains}"
CUPS_DIR="${CUPS_DIR:-${DEPS_DIR}/cups-2.2.4}"
FREETYPE_PREFIX="${FREETYPE_PREFIX:-${DEPS_DIR}/freetype-${ECLIPSE_JRE_ARCH}}"
DUMMY_LIBS="${DUMMY_LIBS:-${DEPS_DIR}/dummy_libs}"

if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    # jdk8 crosses against bionic with the legacy NDK gcc toolchain. The
    # standalone toolchain is built from NDK r10e by prepare-deps.sh.
    TOOLCHAIN="${TOOLCHAIN_ROOT}/r10e-${ECLIPSE_JRE_ARCH}"
    TOOLCHAIN_TYPE="gcc"
    CC="${TOOLCHAIN}/bin/${R10E_PREFIX}-gcc"
    CXX="${TOOLCHAIN}/bin/${R10E_PREFIX}-g++"
    AR="${TOOLCHAIN}/bin/${R10E_PREFIX}-ar"
    RANLIB="${TOOLCHAIN}/bin/${R10E_PREFIX}-ranlib"
    STRIP="${TOOLCHAIN}/bin/${R10E_PREFIX}-strip"
    # 32-bit jdk8 targets run the client VM; 64-bit targets the server VM.
    if [[ "${ECLIPSE_JRE_ARCH}" == "arm" || "${ECLIPSE_JRE_ARCH}" == "x86" ]]; then
        JVM_VARIANT="${JVM_VARIANT:-client}"
    else
        JVM_VARIANT="${JVM_VARIANT:-server}"
    fi
else
    # JDK 17+ crosses with the NDK LLVM clang toolchain (client VM no longer
    # exists; server is the only hotspot variant on Android targets).
    TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
    TOOLCHAIN_TYPE="clang"
    CC="${TOOLCHAIN}/bin/${CLANG_PREFIX}${ANDROID_API}-clang"
    CXX="${TOOLCHAIN}/bin/${CLANG_PREFIX}${ANDROID_API}-clang++"
    AR="${TOOLCHAIN}/bin/llvm-ar"
    RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    STRIP="${TOOLCHAIN}/bin/llvm-strip"
    JVM_VARIANT="${JVM_VARIANT:-server}"
fi

export ANDROID_NDK_VERSION ANDROID_SDK NDK_ROOT ANDROID_API
export ECLIPSE_JRE_VERSION ECLIPSE_JRE_ARCH
export TRIPLE OPENJDK_TARGET CLANG_PREFIX R10E_ARCH R10E_PREFIX
export WORKSPACE SRC_DIR OUT_DIR DEPS_DIR TOOLCHAIN_ROOT
export CUPS_DIR FREETYPE_PREFIX DUMMY_LIBS
export TOOLCHAIN TOOLCHAIN_TYPE CC CXX AR RANLIB STRIP JVM_VARIANT
