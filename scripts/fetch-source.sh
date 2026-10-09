#!/usr/bin/env bash
# Fetch the OpenJDK sources for the requested runtime version.
# DRAFT: shallow clones of the official openjdk u-repos; iterate via CI.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
ECLIPSE_JRE_VERSION="${1:?usage: fetch-source.sh <8|17|21|25>}"
ECLIPSE_JRE_ARCH="${ECLIPSE_JRE_ARCH:-arm64}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env.sh"

case "${ECLIPSE_JRE_VERSION}" in
    8)  REPO_URL="https://github.com/openjdk/jdk8u.git" ;;
    17) REPO_URL="https://github.com/openjdk/jdk17u.git" ;;
    21) REPO_URL="https://github.com/openjdk/jdk21u.git" ;;
    25) REPO_URL="https://github.com/openjdk/jdk25u.git" ;;
    *)
        echo "unknown version: ${ECLIPSE_JRE_VERSION}" >&2
        exit 1
        ;;
esac

rm -rf "${SRC_DIR}"
git clone --depth 1 "${REPO_URL}" "${SRC_DIR}"

{
    echo "jdk version: ${ECLIPSE_JRE_VERSION}"
    echo "source: ${REPO_URL}"
    echo "commit: $(git -C "${SRC_DIR}" rev-parse HEAD)"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "${WORKSPACE}/source-info.txt"
