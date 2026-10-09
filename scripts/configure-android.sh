#!/usr/bin/env bash
# ===========================================================================
# Cross-configure the OpenJDK tree for Android with the resolved toolchain.
#
# Notes on failure detection: jdk8's configure wrapper runs the real
# generated configure behind a `... | tee` pipeline, so its exit status is
# always tee's (0) even when configure aborts. The authoritative signal is
# therefore the generated build/<conf>/spec.gmk, which configure only writes
# on success; both eras are validated against it here.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

BOOT_JDK="${BOOT_JDK:?set BOOT_JDK to the boot JDK home for this version}"

cd "${SRC_DIR}"

# The bundled config.sub revisions predate Android as a target system and
# reject our triples; swap every copy for the vendored modern GNU config.sub,
# which canonicalizes them cleanly (covers both the jdk8u
# common/autoconf/build-aux and the 17+ make/autoconf/build-aux layouts).
while IFS= read -r -d '' bundled; do
    cp "${SCRIPT_DIR}/config.sub" "${bundled}"
    echo "replaced ${bundled} with modern GNU config.sub"
done < <(find "${SRC_DIR}" -name config.sub -print0)

# Sanity checks: the cross toolchain must exist before configure probes it.
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
    # Empty bionic stubs satisfy -lpthread / -lthread_db / -lrt style checks;
# the real symbols live in libc.
    "--with-extra-ldflags=-L${DUMMY_LIBS}"
)

conf_status=0
if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    # jdk8u autoconf rejects the 9+ options (--enable-headless-only,
    # --disable-warnings-as-errors, --disable-dtrace, --with-version-opt,
    # --with-toolchain-type=clang era flags), so this branch only passes
    # options the pinned jdk8u tree understands:
    #   --disable-headful         skip X11 entirely (bionic has no X; the
    #                             launcher supplies its own awt bridge at
    #                             runtime), skips alsa/X11 configure checks
    #   --with-cups-include       cups headers, fatal configure check
    #   --with-fontconfig-include host fontconfig headers (arch-neutral)
    #   --with-freetype-*         per-arch freetype built by prepare-deps
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --disable-headful \
        --disable-jfr \
        --disable-precompiled-headers \
        --with-cups-include="${CUPS_DIR}" \
        --with-fontconfig-include=/usr/include \
        --with-freetype-include="${FREETYPE_PREFIX}/include/freetype2" \
        --with-freetype-lib="${FREETYPE_PREFIX}/lib" \
        || conf_status=$?
else
    # Two configure constraints shape this branch:
    #  1. toolchain-type=clang also inspects the *build-platform* compilers
    #     (BUILD_CC/BUILD_CXX must report "clang" in --version output) and
    #     probes unprefixed ar/nm/strip/objcopy, whose host binutils cannot
    #     index target ELF archives (env values for these are explicitly
    #     ignored by this autoconf era).
    #  2. a target-built freetype is required: the system-freetype check
    #     links a test program against libfreetype, which fails with the
    #     host's x86_64 copy. 'bundled' compiles the in-tree sources with
    #     the target CC instead.
    # A shim dir on PATH resolves both: unprefixed names map to host clang
    # (build helpers) and to NDK llvm-* tools (target-aware, format
    # agnostic). Ar must not remain in the environment so its ignored-value
    # warning does not mask the shim resolution.
    HOST_CLANG="$(command -v clang || true)"
    HOST_CLANGXX="$(command -v clang++ || true)"
    if [[ -z "${HOST_CLANG}" || -z "${HOST_CLANGXX}" ]]; then
        echo "host clang/clang++ not found (needed for build-platform helpers)" >&2
        exit 1
    fi
    SHIM_DIR="${DEPS_DIR}/build-tool-shims"
    mkdir -p "${SHIM_DIR}"
    ln -sf "${HOST_CLANG}" "${SHIM_DIR}/cc"
    ln -sf "${HOST_CLANGXX}" "${SHIM_DIR}/CC"
    ln -sf "${HOST_CLANGXX}" "${SHIM_DIR}/g++"
    for t in ar ranlib strip nm objcopy objdump; do
        ln -sf "${TOOLCHAIN}/bin/llvm-${t}" "${SHIM_DIR}/${t}"
    done
    ln -sf "${TOOLCHAIN}/bin/llvm-objcopy" "${SHIM_DIR}/gobjcopy"
    ln -sf "${TOOLCHAIN}/bin/llvm-objdump" "${SHIM_DIR}/gobjdump"
    export PATH="${SHIM_DIR}:${PATH}"

    # JDK 17+ autoconf: clang toolchain, headless-only image, warnings never
    # fatal for cross builds, no dtrace, no precompiled headers. The clang
    # wrapper already carries --target; repeating it (identical) keeps
    # non-wrapper invocations on the same triple.
    EXTRA_FLAGS="--target=${CLANG_PREFIX}${ANDROID_API} -fPIC"
    env -u AR -u RANLIB -u STRIP CC="${CC}" CXX="${CXX}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --with-toolchain-type=clang \
        --enable-headless-only \
        --disable-warnings-as-errors \
        --disable-dtrace \
        --disable-precompiled-headers \
        --with-freetype=bundled \
        --with-version-opt="eclipse$(date -u +%Y%m%d)" \
        --with-extra-cflags="${EXTRA_FLAGS}" \
        --with-extra-cxxflags="${EXTRA_FLAGS}" \
        || conf_status=$?
fi

# ---------------------------------------------------------------------------
# Verify configure actually completed (see header comment about the jdk8
# wrapper swallowing the exit status), then surface the tail of whatever log
# the failed run produced.
# ---------------------------------------------------------------------------
SPEC_GMK="$(find "${SRC_DIR}/build" -maxdepth 3 -name spec.gmk -print -quit 2>/dev/null || true)"
if [[ -z "${SPEC_GMK}" ]]; then
    echo "configure did not produce spec.gmk (raw status ${conf_status})" >&2
    while IFS= read -r -d '' log; do
        echo "==== tail of ${log} ====" >&2
        tail -n 60 "${log}" >&2
    done < <(find "${SRC_DIR}" -maxdepth 3 \( -name configure.log -o -name config.log \) -print0 2>/dev/null)
    exit 1
fi

echo "configure finished; spec.gmk: ${SPEC_GMK}"
echo "SPEC_GMK=${SPEC_GMK}" >> "${GITHUB_ENV:-/dev/null}"
