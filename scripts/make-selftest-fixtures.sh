#!/usr/bin/env bash
set -euo pipefail

## Generates a stand-in for the per-architecture build artifacts so the
## packaging, manifest and release steps can be exercised without spending 40
## minutes per JDK build. The fixtures are shaped exactly like the real build
## outputs (same filenames, same internal layout the repack scripts consume), so
## the same downstream code runs unmodified.

if [[ $# -ne 2 ]]; then
  echo "usage: $0 INCOMING_DIR STUB_BIN_DIR" >&2
  exit 2
fi

incoming="$1"
stub_bin="$2"
mkdir -p "$incoming" "$stub_bin"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The real pack200 is a JDK 8 binary that rejects the synthetic fixture jars.
# Stubbing it isolates the packaging logic under test from the JDK build.
# repackjre.sh calls `pack200 <options> input.jar output.jar`, so the last two
# arguments are the source and destination.
cat >"$stub_bin/pack200" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exec cp "${@: -2:1}" "${@: -1}"
STUB
mkdir -p "$stub_bin"
cat >"$stub_bin/pack200" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exec cp "${@: -2:1}" "${@: -1}"
STUB
chmod +x "$stub_bin/pack200"
echo "self-test: using pack200 stub from $stub_bin (real pack200 cannot read fixture jars)"

date_stamp="$(date -u +%Y%m%d)"

make_fixture() {
  local version="$1" arch="$2" jvm_subdir="$3"
  local root="$scratch/$version-$arch"
  rm -rf "$root"
  mkdir -p "$root/bin" "$root/lib/$jvm_subdir/server"

  cat >"$root/bin/java" <<'EXEC'
#!/bin/sh
exit 0
EXEC
  chmod +x "$root/bin/java"

  printf 'fixture\n' >"$root/lib/$jvm_subdir/server/libjvm.so"
  printf 'fixture\n' >"$root/lib/libnet.so"
  printf 'fixture\n' >"$root/lib/jexec"
  printf 'fixture\n' >"$root/release"

  if [[ "$version" == "8" ]]; then
    # repackjre.sh deletes these before packing an architecture component.
    for tool in rmid keytool rmiregistry tnameserv policytool orbd servertool; do
      printf 'fixture\n' >"$root/bin/$tool"
    done
    # makeuni() strips lib/<arch dir>, lib/jfr and man/ from the universal part.
    mkdir -p "$root/lib/jfr" "$root/man" "$root/lib/ext"
    printf 'fixture\n' >"$root/lib/rt.jar"
    printf 'fixture\n' >"$root/lib/ext/zipfs.jar"
  else
    printf 'fixture\n' >"$root/lib/jvm.cfg"
    # makeuni() strips lib/server from the universal part and expects a
    # modular runtime image to remain.
    mkdir -p "$root/lib/jli" "$root/lib/server"
    printf 'fixture\n' >"$root/lib/modules"
    printf 'fixture\n' >"$root/lib/jli/libjli.so"
  fi

  tar -cJf "$incoming/jre${version}-${arch}-${date_stamp}-release.tar.xz" -C "$root" .

  printf 'java_version=%s\nandroid_arch=%s\nproject_commit=self-test\n' \
    "$version" "$arch" >"$incoming/build-manifest-jre${version}-${arch}.txt"

  if [[ "$version" == "8" ]]; then
    mkdir -p "$root/.debuginfo"
    printf 'fixture\n' >"$root/.debuginfo/libjvm.debuginfo"
    tar -cJf "$incoming/debuginfo-jre${version}-${arch}-${date_stamp}-release.tar.xz" \
      -C "$root/.debuginfo" .
  fi
}

# arch name -> directory that holds libjvm.so inside the raw build output.
for version in 8 17 21 25; do
  for arch in arm arm64 x86 x86_64; do
    if [[ "$version" == "25" && "$arch" == "x86" ]]; then
      continue  # Java 25 is not built for 32-bit x86
    fi
    case "$arch" in
      arm) jvm_subdir=aarch32 ;;
      arm64) jvm_subdir=aarch64 ;;
      x86) jvm_subdir=i386 ;;
      x86_64) jvm_subdir=amd64 ;;
    esac
    make_fixture "$version" "$arch" "$jvm_subdir"
  done
done

raw="$(find "$incoming" -maxdepth 1 -type f -name 'jre*-release.tar.xz' | wc -l)"
manifests="$(find "$incoming" -maxdepth 1 -type f -name 'build-manifest-jre*.txt' | wc -l)"
debuginfo="$(find "$incoming" -maxdepth 1 -type f -name 'debuginfo-*.tar.xz' | wc -l)"
echo "self-test: generated $raw per-architecture tarballs, $manifests build manifests, $debuginfo debuginfo tarballs"
if [[ "$raw" -ne 15 || "$manifests" -ne 15 || "$debuginfo" -ne 4 ]]; then
  echo "self-test fixture set is incomplete" >&2
  exit 1
fi