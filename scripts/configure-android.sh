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
    # JDK 17+ autoconf: clang toolchain, headless-only image, warnings never
    # fatal for cross builds, no dtrace, no precompiled headers.
    EXTRA_FLAGS="--target=${TRIPLE}${ANDROID_API} -fPIC"
    CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
    bash configure "${COMMON_FLAGS[@]}" \
        --with-toolchain-type=clang \
        --enable-headless-only \
        --disable-warnings-as-errors \
        --disable-dtrace \
        --disable-precompiled-headers \
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
