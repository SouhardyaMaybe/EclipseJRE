#!/usr/bin/env bash
# ===========================================================================
# Android/bionic adaptation edits for the vanilla OpenJDK tree fetched by
# fetch-source.sh.
#
# Vanilla OpenJDK targets glibc/Linux; bionic is missing a small set of libc
# surface areas (legacy mode macros, glibc-shaped ucontext accessors, ...).
# Every fix lives here as a minimal, targeted edit with an assertion that
#   - fails loudly if the pinned source no longer contains the old form
#     (pin drift must never pass silently), and
#   - fails if the replacement did not take.
#
# Blocks are grouped by the JDK era that carries the affected file. Each
# block cites the compiler error that motivated it, so this file doubles as
# the port's change log.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

cd "${SRC_DIR}"

# Replace every occurrence of a token tree-wide (arguments must be plain
# identifiers; the pipe-delimited sed expression relies on that).
replace_tree() {
    local old="$1" new="$2" why="$3"
    local hits
    hits="$(grep -rlF --exclude-dir=.git -- "${old}" . || true)"
    if [[ -z "${hits}" ]]; then
        if ! grep -rqF --exclude-dir=.git -- "${new}" .; then
            echo "port-fix: '${old}' not found and '${new}' absent too -" \
                 "source pin drifted for: ${why}" >&2
            exit 1
        fi
        echo "port-fix: '${old}' already absent (${why})"
        return 0
    fi
    # shellcheck disable=SC2086
    grep -rlF --exclude-dir=.git -- "${old}" . | xargs -r sed -i \
        "s|${old}|${new}|g"
    if grep -rqF --exclude-dir=.git -- "${old}" .; then
        echo "port-fix: '${old}' still present after replacement (${why})" >&2
        exit 1
    fi
    echo "port-fix: ${old} -> ${new} (${why})"
}

case "${ECLIPSE_JRE_VERSION}" in
8)
    # attachListener_linux.cpp (and any sibling) used the legacy BSD mode
    # spellings glibc exposes but bionic does not declare; the values are
    # identical to S_IRUSR/S_IWUSR, so this is a pure rename.
    #   error: 'S_IREAD' was not declared in this scope
    #   error: 'S_IWRITE' was not declared in this scope
    replace_tree "S_IREAD" "S_IRUSR" \
        "bionic lacks legacy chmod mode macros (attachListener_linux.cpp)"
    replace_tree "S_IWRITE" "S_IWUSR" \
        "bionic lacks legacy chmod mode macros (attachListener_linux.cpp)"
    ;;
17|21|25)
    echo "no port fixes recorded yet for jdk${ECLIPSE_JRE_VERSION}"
    ;;
*)
    echo "unknown ECLIPSE_JRE_VERSION: ${ECLIPSE_JRE_VERSION}" >&2
    exit 1
    ;;
esac

echo "port fixes applied for jdk${ECLIPSE_JRE_VERSION}-${ECLIPSE_JRE_ARCH}"
