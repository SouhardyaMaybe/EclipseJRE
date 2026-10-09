#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 VERSION ASSETS_DIR BUILD_ID RELEASE_TAG OUTPUT_FILE" >&2
  exit 2
fi

version="$1"
assets_dir="$2"
build_id="$3"
release_tag="$4"
output="$5"

case "$version" in
  8|17|21|25) ;;
  *) echo "unsupported version: $version" >&2; exit 2 ;;
esac

# A release has a single flat asset namespace, so every published component
# carries a `jre<N>-` prefix. Those prefixed names are the only filenames a
# client has to know.
universal_name="jre${version}-universal.tar.xz"

# The name token each architecture uses in a component filename, the Android ABI
# that token corresponds to, and the order components appear in the manifest.
# Fixing the order keeps the file byte-stable across releases.
arch_token=()
arch_abi=()
add_arch() {
  arch_token+=("$1")
  arch_abi+=("$2")
}
add_arch arm armeabi-v7a
add_arch arm64 arm64-v8a
add_arch x86 x86
add_arch x86_64 x86_64

# Both fields are inlined into JSON, so reject anything that is not the shape the
# repack scripts produce: `version` holds either the source commit or a build
# date, and the tag has to match the format the release step accepts.
if [[ ! "$build_id" =~ ^([0-9a-f]{7,40}|[0-9]{8})$ ]]; then
  echo "unexpected build identifier: $build_id" >&2
  exit 1
fi
if [[ ! "$release_tag" =~ ^jres-v[0-9A-Za-z._-]+$ ]]; then
  echo "unexpected release tag: $release_tag" >&2
  exit 1
fi

digest_and_size() {
  local file="$1"
  [[ -s "$file" ]] || { echo "missing or empty: $file" >&2; exit 1; }
  printf '%s %s\n' "$(sha256sum "$file" | cut -d' ' -f1)" "$(wc -c <"$file")"
}

universal_sha=""
universal_size=""
read -r universal_sha universal_size < <(digest_and_size "$assets_dir/$universal_name")

# Membership comes from what is actually published, not from a hardcoded
# version/arch matrix: Java 25 has no 32-bit x86 runtime, and duplicating that
# matrix here would create a second thing to keep in sync with the build.
# scripts/verify-bundle.sh has already validated the bundle directory this
# manifest's components are copied from.
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
found=0
for ((i = 0; i < ${#arch_token[@]}; i++)); do
  component="jre${version}-bin-${arch_token[$i]}.tar.xz"
  [[ -s "$assets_dir/$component" ]] || continue
  read -r sha size < <(digest_and_size "$assets_dir/$component")
  [[ $found -eq 0 ]] || printf ',\n' >>"$body"
  printf '    {\n      "arch": "%s",\n      "android_abi": "%s",\n      "name": "%s",\n      "sha256": "%s",\n      "size": %s\n    }' \
    "${arch_token[$i]}" "${arch_abi[$i]}" "$component" "$sha" "$size" >>"$body"
  found=$((found + 1))
done
if [[ $found -eq 0 ]]; then
  echo "no per-architecture components published for Java $version in $assets_dir" >&2
  exit 1
fi

{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "java_version": %s,\n' "$version"
  printf '  "build_id": "%s",\n' "$build_id"
  printf '  "release_tag": "%s",\n' "$release_tag"
  printf '  "universal": {\n'
  printf '    "name": "%s",\n' "$universal_name"
  printf '    "sha256": "%s",\n' "$universal_sha"
  printf '    "size": %s\n' "$universal_size"
  printf '  },\n'
  printf '  "architectures": [\n'
  cat "$body"
  printf '\n  ]\n'
  printf '}\n'
} >"$output"

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$output" ||
  { echo "generated manifest is not valid JSON: $output" >&2; exit 1; }