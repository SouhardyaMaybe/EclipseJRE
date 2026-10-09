# EclipseJRE

Pipeline for cross-compiling OpenJDK 8/17/21/25 runtimes for Android
(arm, arm64, x86, x86_64) in the exact "binpack" layout the Eclipse Launcher
consumes from its assets.

**Status: DRAFT skeleton.** The workflow and scripts are written to be run and
iterated via CI; no successful build has been produced yet. Expect the
configure flags and the binpack split rules to need fixes on the first runs.

## Artifact contract

The launcher (`UnpackJreTask` + `MultiRTUtils.installRuntimeNamedBinpack`)
expects, per runtime, these files under
`EclipseLauncher/src/main/assets/components/jre-<version>/`:

| File | Content |
|---|---|
| `universal.tar.xz` | arch-independent runtime files (extracted first) |
| `bin-arm.tar.xz` | 32-bit ARM files (`bin/` launchers + arch-specific libs), extracted over the universal tree |
| `bin-arm64.tar.xz` | same for AArch64 |
| `bin-x86.tar.xz` | same for 32-bit x86 |
| `bin-x86_64.tar.xz` | same for x86-64 |
| `version` | opaque text stamp compared against the installed runtime; any changing value works (date or source commit) |

The per-ABI APK pruning in `EclipseLauncher/build.gradle.kts` keeps exactly
`version`, `universal*`, and `bin-<arch>.tar.xz` for split builds, so the file
names above are load-bearing.

After extraction the launcher renames `libfreetype.so.6` to `libfreetype.so`
and drops a dummy `libawt_xawt.so` (`MultiRTUtils.postPrepare`); no
convention change is needed for those on our side.

## Sources

| Runtime | Source repo | Notes |
|---|---|---|
| JDK 8 | https://github.com/openjdk/jdk8u | needs JDK 8 boot JDK |
| JDK 17 | https://github.com/openjdk/jdk17u | needs JDK 16/17 boot JDK |
| JDK 21 | https://github.com/openjdk/jdk21u | needs JDK 20/21 boot JDK |
| JDK 25 | https://github.com/openjdk/jdk25u | needs JDK 24 boot JDK |

Toolchain: Android NDK 25.2.9519653, `--openjdk-target` cross builds with the
NDK clang compilers, headless-only AWT, client VM for JDK 8 and server VM for
17+ (both options are drafts - see `docs/plan.md`).

## Repository layout

```
docs/plan.md            full pipeline plan and open questions
scripts/env.sh          common environment (triples, NDK paths)
scripts/fetch-source.sh clone the OpenJDK source for a version
scripts/configure-android.sh  autoconf cross-configure  [FIRST DRAFT]
scripts/build-android.sh      make the JDK image        [FIRST DRAFT]
scripts/package-binpack.sh    split universal/bin tarballs, xz -T0, version stamp
.github/workflows/build-jre.yml  matrix over version x arch; tag-triggered publishing
```

## Building

CI is the only supported build path for now:

- manual: run the `build-jre` workflow from the Actions tab
  (workflow_dispatch)
- automatic: push a tag matching `jre-*`

Each matrix cell (version x arch) builds one `bin-<arch>.tar.xz`; the
`assemble` job merges everything into the per-version asset layout and (on
tags) attaches the files to the GitHub publish job under
`jre-<version>-*` names. The app repo pins those URLs and copies the files
into its `assets/components/jre-<version>/` directory.

Local iteration is possible by running the `scripts/` in order inside an
Ubuntu container with the NDK installed, but that is not documented end-to-end
yet - CI runs are the feedback loop.

## Known open items

- The universal/bin file split must be validated against the launcher's
  extraction order (universal first, then bin overlaid).
- freetype: bundled vs system, and the `.so.6` rename contract.
- JDK 8 pack200 handling (`unpack200` runs from the launcher's native lib
  dir).
- CACIO/AWT headless classes must land in the universal tarball
  (launcher adds caciocavallo via bootclasspath at launch time).

See `docs/plan.md` for the full list.
