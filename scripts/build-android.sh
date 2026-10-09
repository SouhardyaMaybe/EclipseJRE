#!/usr/bin/env bash
# ===========================================================================
# FIRST DRAFT - build the JDK image after configure-android.sh.
# Iterate via CI runs; expect per-version tweaks.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

cd "${SRC_DIR}"

JOBS="${JOBS:-$(nproc)}"

# Older jdk8u trees build a named configuration directory; newer trees use
# build/<os>-<arch>-<jvm>-<debuglevel>. Resolve it instead of hardcoding.
BUILD_DIR="$(find "${SRC_DIR}/build" -maxdepth 1 -mindepth 1 -type d | head -n1)"
if [[ -z "${BUILD_DIR}" ]]; then
    echo "no build directory found - did configure run?" >&2
    exit 1
fi

make -C "${BUILD_DIR}" -j"${JOBS}" images

IMAGE_DIR="$(find "${BUILD_DIR}" -maxdepth 2 -type d -name image | head -n1)"
if [[ -z "${IMAGE_DIR}" ]]; then
    echo "no JDK image directory produced" >&2
    exit 1
fi

echo "IMAGE_DIR=${IMAGE_DIR}" >> "${GITHUB_ENV:-/dev/null}"
echo "built image: ${IMAGE_DIR}"
ls "${IMAGE_DIR}/jre" 2>/dev/null || ls "${IMAGE_DIR}"
