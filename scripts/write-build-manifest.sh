#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: $0 VERSION ARCH PROJECT_COMMIT LOCAL_RECIPE_SHA256 OPENJDK_SOURCE_DIR NDK_VERSION OUTPUT_FILE" >&2
  exit 2
fi

version="$1"
arch="$2"
project_commit="$3"
recipe_sha256="$4"
source_dir="$5"
ndk_version="$6"
output="$7"

case "$version" in
  8|17|21|25) ;;
  *) echo "unsupported version: $version" >&2; exit 2 ;;
esac

if [[ -d "$source_dir/.git" ]]; then
  openjdk_commit="$(git -C "$source_dir" rev-parse HEAD)"
else
  echo "OpenJDK source checkout not found: $source_dir" >&2
  exit 1
fi

{
  printf 'java_version=%s\n' "$version"
  printf 'android_arch=%s\n' "$arch"
  printf 'android_api=21\n'
  printf 'android_ndk=%s\n' "$ndk_version"
  printf 'project_commit=%s\n' "$project_commit"
  printf 'local_recipe_sha256=%s\n' "$recipe_sha256"
  printf 'openjdk_commit=%s\n' "$openjdk_commit"
  printf 'built_at_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} > "$output"
