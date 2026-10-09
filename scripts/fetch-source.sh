#!/usr/bin/env bash
# Fetch a pinned OpenJDK source tree for one runtime version.
#
# Pins (reproducible builds, recorded in source-info.txt):
#   jdk8 arm    - aarch32 port of jdk8u (mainline jdk8u has no 32-bit ARM
#                 hotspot), latest 8u522 tag
#   jdk8 else   - jdk8u462-ga (last release before the upstream aarch64
#                 GCC-5 guard, which our r10e GCC 4.9 toolchain predates)
#   jdk17       - jdk17u tip (rolling 17.0.x updates; SHA recorded)
#   jdk21       - jdk-21.0.12+5
#   jdk25       - jdk-25.0.4+4

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
ECLIPSE_JRE_VERSION="${1:?usage: fetch-source.sh <8|17|21|25>}"
ECLIPSE_JRE_ARCH="${ECLIPSE_JRE_ARCH:-arm64}"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

case "${ECLIPSE_JRE_VERSION}" in
    8)
        if [[ "${ECLIPSE_JRE_ARCH}" == "arm" ]]; then
            REPO_URL="https://github.com/openjdk/aarch32-port-jdk8u.git"
            REPO_REF="jdk8u522-b00"
        else
            REPO_URL="https://github.com/openjdk/jdk8u.git"
            REPO_REF="jdk8u462-ga"
        fi
        ;;
    17)
        REPO_URL="https://github.com/openjdk/jdk17u.git"
        REPO_REF="master"
        ;;
    21)
        REPO_URL="https://github.com/openjdk/jdk21u.git"
        REPO_REF="jdk-21.0.12+5"
        ;;
    25)
        REPO_URL="https://github.com/openjdk/jdk25u.git"
        REPO_REF="jdk-25.0.4+4"
        ;;
    *)
        echo "unknown version: ${ECLIPSE_JRE_VERSION}" >&2
        exit 1
        ;;
esac

rm -rf "${SRC_DIR}"
git clone --depth 1 --branch "${REPO_REF}" "${REPO_URL}" "${SRC_DIR}"

{
    echo "jdk version: ${ECLIPSE_JRE_VERSION}"
    echo "source: ${REPO_URL}"
    echo "ref: ${REPO_REF}"
    echo "commit: $(git -C "${SRC_DIR}" rev-parse HEAD)"
    echo "arch: ${ECLIPSE_JRE_ARCH}"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "${WORKSPACE}/source-info.txt"
