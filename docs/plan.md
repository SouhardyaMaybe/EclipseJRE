# EclipseJRE pipeline plan

Goal: build OpenJDK 8, 17, 21 and 25 for Android (arm / arm64 / x86 /
x86_64) in CI and produce the binpack artifact layout the Eclipse Launcher
already consumes. This document is the working plan; items marked DRAFT are
expected to be corrected through CI iteration.

## 1. Artifact contract (from the app, read-only inspection)

- `assets/components/jre-<v>/{universal.tar.xz, bin-<arch>.tar.xz, version}`
- `version` is an opaque string; the launcher re-unpacks when it differs from
  the installed runtime's stamp. Use `<git-describe>-<date>` of the OpenJDK
  source build.
- Extraction: universal first, then the arch binpack overlaid onto the same
  directory (`installRuntimeNamedBinpack`). Both tarballs must contain paths
  relative to the runtime root (`bin/`, `lib/`, `conf/`, ...).
- Arch mapping used by the launcher: `arm` = 32-bit ARM (armeabi-v7a),
  `arm64` = AArch64, `x86`, `x86_64`.

### Binpack split (DRAFT - validate on first builds)

- `universal.tar.xz`: everything except arch-specific binaries:
  `lib/modules`, `lib/security/`, `lib/ext/`, `lib/rt.jar` (JDK 8),
  `lib/charsets.jar`, `lib/cacerts`, `conf/`, `legal/`, `lib/*.jar`,
  non-arch `lib/*.properties`, `include/` not needed (strip).
- `bin-<arch>.tar.xz`: `bin/java` & friends (the ELF launchers, not the shell
  wrappers), `lib/jli/`, `lib/server/`, `lib/client/` (JDK 8), and the
  arch-specific library directory the launcher's `runtime.arch` expects
  (`lib/arm`, `lib/aarch64`, `lib/x86`, `lib/x86_64` naming to be confirmed
  against `MultiRTUtils.read(...)` during CI validation).

## 2. Source matrix

| Version | Repo | Boot JDK (DRAFT) | JVM variant (DRAFT) |
|---|---|---|---|
| 8 | github.com/openjdk/jdk8u | temurin 8 | client |
| 17 | github.com/openjdk/jdk17u | temurin 17 | server |
| 21 | github.com/openjdk/jdk21u | temurin 21 | server |
| 25 | github.com/openjdk/jdk25u | temurin 24 | server |

Clone with `--depth 1`. For reproducible stamps, record `git rev-parse HEAD`
into the `version` file alongside the build date.

Useful community references for Android OpenJDK ports (read-only):
PojavLauncherTeam/android-openjdk-build-multiarch,
PojavLauncherTeam/openjdk-multiarch-jdk8u, ShirasakiMio/android-openjdk-build,
FCL-Team/Android-OpenJDK-Build.

## 3. Toolchain

- Runner: `ubuntu-latest` (6h job cap; JDK client builds usually fit,
  server-VM builds of 21/25 may need ccache or bigger runners - open item).
- Android NDK 25.2.9519653 via `android-actions/setup-android` +
  `sdkmanager "ndk;25.2.9519653"`.
- Target triples:
  - arm -> `armv7a-linux-androideabi21` (old autoconf target
    `arm-linux-androideabi` for jdk8u)
  - arm64 -> `aarch64-linux-android21`
  - x86 -> `i686-linux-android21`
  - x86_64 -> `x86_64-linux-android21`
- `CC`/`CXX` point at the NDK clang/clang++ wrappers; `--openjdk-target` is
  passed to configure. `--with-freetype=bundled` (DRAFT; Android has no
  system freetype for the JDK to link).

## 4. Configure/build flags (FIRST DRAFT)

Common: `--with-debug-level=release --with-native-debug-symbols=none
--disable-werror --enable-headless-only --disable-jfr` (8 has no JFR)
`--disable-dtrace --with-zlib=system` (NDK provides zlib).

JDK 8 extras: `--with-jvm-variants=client`, `--disable-precompiled-headers`
if the cross toolchain trips it, `--with-version-opt` for the stamp.

JDK 17/21/25 extras: `--with-jvm-variants=server --with-jvm-features=shenandoahgc`
(25: confirm default GC set instead), `--disable-hotspot-gc` options as
revealed by configure errors.

Headless-only removes the X11 AWT peers; the launcher supplies AWT via the
caciocavallo modules at runtime, so the JDK must keep
`libawt_headless`/`libfontmanager` and drop `libawt_xawt` (the launcher
replaces it with a dummy .so at post-prepare time anyway).

## 5. Packaging

`scripts/package-binpack.sh <version> <arch>`:

1. `make images` output lives in `build/<linux-<arch>-server-or-client-release/image>`.
2. Split per the table in section 1 into `universal/` and `bin-<arch>/`
   staging dirs.
3. Strip all ELF files (`${TRIPLE}-strip` from the NDK toolchain, or
   `llvm-strip`).
4. `tar -c -- xz` each staging dir with `xz -T0` into
   `out/jre-<v>/universal.tar.xz` and `out/jre-<v>/bin-<arch>.tar.xz`.
5. Write `out/jre-<v>/version` as
   `<jdk-version>+<git-short-hash>-<yyyyMMdd>`.

JDK 8 pack200: the launcher's `unpack200` step expects packed `.pack` files
next to the runtime; decide during CI validation whether to emit pack200
artifacts for JDK 8 or to skip (open item).

## 6. CI shape

`.github/workflows/build-jre.yml`:

- triggers: `workflow_dispatch` (manual, optionally filtered) and tag pushes
  matching `jre-*`.
- `build` job: matrix `version: [8, 17, 21, 25]` x
  `arch: [arm, arm64, x86, x86_64]` (16 cells, fail-fast off).
  Steps: checkout, setup-java (Gradle-free; JDK 21 host + boot JDK),
  setup-android + NDK, disk cleanup step (dotnet/ghc are large and unused),
  fetch source, configure, build, package, upload `jre-<v>-bin-<arch>`
  artifact.
- `assemble` job: per version, download the 4 bin artifacts + build universal
  from the arm64 cell (DRAFT: universal is identical across arches; deriving
  it from one cell avoids 4x duplication), lay out the exact
  `jre-<v>/` asset structure, upload one `jre-<v>` artifact; on tag runs
  attach the files to the GitHub publish job with `jre-<v>-` prefixes
  (release assets are flat).

## 7. Open questions / risks

- Build time of server-VM JDK 21/25 on hosted runners; may need
  larger runners, ccache, or reduced feature sets.
- freetype bundling vs NDK-provided; the launcher renames
  `libfreetype.so.6` -> `libfreetype.so`, so the built image must ship the
  `.so.6` name (or the contract changes in the app later).
- Exact arch lib directory naming (`lib/aarch32` in Pojav logs vs
  `lib/arm`) must match what `MultiRTUtils.read` resolves for
  `runtime.arch`.
- JDK 8: pack200 presence, `tools.jar`/`jexec` handling.
- Shenandoah/ZGC availability per Android target; defaults may need
  restricting to HotSpot GCs that pass on Android kernels.
- Determinism: xz -T0 produces identical output for identical input; the
  `version` stamp is the only intended per-build difference.
