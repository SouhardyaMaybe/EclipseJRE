#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 VERSION BUNDLE_DIRECTORY" >&2
  exit 2
fi

# Listing an archive and matching it in the same pipeline is not safe under
# `set -o pipefail`. `grep -q` exits on the first match and closes the pipe,
# so tar keeps writing the rest of the listing, dies with SIGPIPE and reports
# "tar: stdout: write error". pipefail then hands us a non-zero status that is
# indistinguishable from "pattern not found", so a perfectly good archive was
# rejected as missing bin/java. Write the listing to a file first so tar and
# grep never share a pipe.
listing=""
cleanup() { [[ -n "$listing" ]] && rm -f "$listing"; }
trap cleanup EXIT

# Populates $listing with the archive contents.
# Returns 0 on success, 2 if the archive cannot be read.
build_listing() {
  local archive="$1"
  cleanup
  listing="$(mktemp)"
  if ! tar -tJf "$archive" >"$listing" 2>/dev/null; then
    cleanup
    echo "cannot read archive: $archive" >&2
    return 2
  fi
}

# Returns 0 if the listing matches, 1 if it does not.
listing_has() {
  grep -Eq -- "$1" "$listing"
}

# Prints a description of what the archive does contain, so a rejection is
# actionable instead of just saying the expected entry was missing.
describe_listing() {
  local archive="$1"
  echo "  archive contains $(wc -l <"$listing") entries, first few:" >&2
  head -n 10 "$listing" | sed 's/^/    /' >&2
  echo "  full listing: tar -tJf $archive" >&2
}

version="$1"
bundle_dir="$2"
case "$version" in
  8|17|21) arches=(arm arm64 x86 x86_64) ;;
  25) arches=(arm arm64 x86_64) ;;
  *) echo "unsupported runtime version: $version" >&2; exit 2 ;;
esac

for required in universal.tar.xz version; do
  [[ -s "$bundle_dir/$required" ]] || { echo "missing or empty: $bundle_dir/$required" >&2; exit 1; }
done

for arch in "${arches[@]}"; do
  archive="$bundle_dir/bin-$arch.tar.xz"
  [[ -s "$archive" ]] || { echo "missing or empty: $archive" >&2; exit 1; }
  build_listing "$archive" || exit 2
  if ! listing_has '(^|/)bin/java$'; then
    echo "no java executable in $archive" >&2
    describe_listing "$archive"
    exit 1
  fi
  if ! listing_has '(^|/)lib/([^/]+/)?(server|client)/libjvm\.so$'; then
    echo "no JVM shared library in $archive" >&2
    describe_listing "$archive"
    exit 1
  fi
done

if [[ "$version" == "8" ]]; then
  payload_pattern='(^|/)lib/rt\.jar(\.pack)?$'
  payload_description='Java 8 rt.jar (or its packed form)'
else
  payload_pattern='(^|/)lib/modules$'
  payload_description='modular runtime image'
fi
build_listing "$bundle_dir/universal.tar.xz" || exit 2
if ! listing_has "$payload_pattern"; then
  echo "no $payload_description in universal.tar.xz" >&2
  describe_listing "$bundle_dir/universal.tar.xz"
  exit 1
fi

echo "Java $version bundle structure verified ($bundle_dir)"
