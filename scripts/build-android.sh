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

# jdk8's legacy makefiles honor the JOBS variable; both eras honor -j.
make -C "${BUILD_DIR}" -j"${JOBS}" JOBS="${JOBS}" images

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
