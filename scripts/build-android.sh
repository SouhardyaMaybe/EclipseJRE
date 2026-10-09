#!/usr/bin/env bash
# ===========================================================================
# Build the JDK image after configure-android.sh.
#
# Locates the configured build directory by its spec.gmk (written only by a
# successful configure), runs `make images`, and resolves the image dir that
# package-binpack.sh consumes:
#   jdk8   -> build/<conf>/j2re-image
#   jdk17+ -> build/<conf>/images/jdk   (packaged further via jlink)
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

cd "${SRC_DIR}"

JOBS="${JOBS:-$(nproc)}"

SPEC_GMK="$(find "${SRC_DIR}/build" -maxdepth 3 -name spec.gmk -print -quit 2>/dev/null || true)"
if [[ -z "${SPEC_GMK}" ]]; then
    echo "no spec.gmk under ${SRC_DIR}/build - did configure succeed?" >&2
    exit 1
fi
BUILD_DIR="$(dirname "${SPEC_GMK}")"
echo "building in ${BUILD_DIR} (${JVM_VARIANT} VM, ${ECLIPSE_JRE_ARCH})"

# Two build-invocation constraints:
# - Parallelism goes through JOBS only: jdk8's Main.gmk hard-rejects -j
#   ("make -j is not supported, use make JOBS=n") and jdk17+'s Init.gmk
#   derives its -j from $(JOBS) (serial when empty).
# - WARNINGS_ARE_ERRORS= clears jdk8 hotspot's gcc.make -Werror: the adlc
#   build helper is compiled by the modern host gcc (13), whose
#   format-overflow diagnostics on upstream sprintf calls are fatal there.
#   The command-line assignment overrides the makefile's plain "=" and
#   propagates to every sub-make; 17+ ignores it (its gate is the
#   spec-level WARNINGS_AS_ERRORS=false from --disable-warnings-as-errors).
make -C "${BUILD_DIR}" JOBS="${JOBS}" WARNINGS_ARE_ERRORS= images

if [[ "${ECLIPSE_JRE_VERSION}" == "8" ]]; then
    IMAGE_DIR="${BUILD_DIR}/j2re-image"
else
    IMAGE_DIR="${BUILD_DIR}/images/jdk"
fi

if [[ ! -d "${IMAGE_DIR}" ]]; then
    echo "expected image directory not produced: ${IMAGE_DIR}" >&2
    find "${BUILD_DIR}" -maxdepth 2 -type d >&2
    exit 1
fi
if [[ ! -f "${IMAGE_DIR}/release" ]]; then
    echo "image is missing its release file: ${IMAGE_DIR}/release" >&2
    exit 1
fi

echo "IMAGE_DIR=${IMAGE_DIR}" >> "${GITHUB_ENV:-/dev/null}"
echo "built image: ${IMAGE_DIR}"
