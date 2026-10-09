#!/usr/bin/env bash
# Common environment for the EclipseJRE cross-build scripts.
# Source this from the other scripts. DRAFT: values are validated via CI runs.

set -euo pipefail

ECLIPSE_JRE_VERSION="${ECLIPSE_JRE_VERSION:?set ECLIPSE_JRE_VERSION to 8, 17, 21 or 25}"
ECLIPSE_JRE_ARCH="${ECLIPSE_JRE_ARCH:?set ECLIPSE_JRE_ARCH to arm, arm64, x86 or x86_64}"

# Android API level targeted by the NDK toolchain wrappers.
ANDROID_API="${ANDROID_API:-21}"
NDK_VERSION="${NDK_VERSION:-25.2.9519653}"
NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}/ndk/${NDK_VERSION}}"

# Host tools.
HOST_TAG="${HOST_TAG:-linux-x86_64}"
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"

case "${ECLIPSE_JRE_ARCH}" in
    arm)
        TRIPLE="armv7a-linux-androideabi"      # NDK clang prefix
        OPENJDK_TARGET="arm-linux-androideabi" # jdk8u-style autoconf target
        ;;
    arm64)
        TRIPLE="aarch64-linux-android"
        OPENJDK_TARGET="aarch64-linux-android"
        ;;
    x86)
        TRIPLE="i686-linux-android"
        OPENJDK_TARGET="i686-linux-android"
        ;;
    x86_64)
        TRIPLE="x86_64-linux-android"
        OPENJDK_TARGET="x86_64-linux-android"
        ;;
    *)
        echo "unknown arch: ${ECLIPSE_JRE_ARCH}" >&2
        exit 1
        ;;
esac

CC="${TOOLCHAIN}/${TRIPLE}${ANDROID_API}-clang"
CXX="${TOOLCHAIN}/${TRIPLE}${ANDROID_API}-clang++"
AR="${TOOLCHAIN}/llvm-ar"
RANLIB="${TOOLCHAIN}/llvm-ranlib"
STRIP="${TOOLCHAIN}/llvm-strip"

# Where the OpenJDK source tree is checked out and where outputs land.
WORKSPACE="${WORKSPACE:-${GITHUB_WORKSPACE:-$(pwd)}}"
SRC_DIR="${SRC_DIR:-${WORKSPACE}/openjdk-src}"
OUT_DIR="${OUT_DIR:-${WORKSPACE}/out/jre-${ECLIPSE_JRE_VERSION}}"

# JVM variant: client VM for JDK 8, server VM for 17+ (DRAFT).
if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    JVM_VARIANT="${JVM_VARIANT:-client}"
else
    JVM_VARIANT="${JVM_VARIANT:-server}"
fi

export TRIPLE OPENJDK_TARGET ANDROID_API NDK_ROOT TOOLCHAIN CC CXX AR RANLIB STRIP
export WORKSPACE SRC_DIR OUT_DIR JVM_VARIANT
