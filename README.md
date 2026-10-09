# Eclipse JRE pipeline

Builds the Android OpenJDK runtimes (**8, 17, 21, and 25**) that ship inside
Eclipse Launcher. Scripts, patch sets and repacking recipes live in this
repository; OpenJDK source and the Android NDK are fetched during the build.

## Run or rerun a build

1. Open **Actions** → **Eclipse JRE pipeline**.
2. In the **Run workflow** form, select an existing `jres-v*` tag in the
   **Use workflow from** menu and enter the tag to publish to.
3. Click **Run workflow**.

The normal build and packaging steps run. On success, the JRE ZIPs, per-ABI
`bin-<arch>.tar.xz` components, `universal.tar.xz`, manifests and checksums
appear on that tag's **Releases** page.

## Make a new bundle

Push a new tag, for example `jres-v1.0.0`. The workflow starts automatically
and publishes after all 15 architecture builds pass.

## Outputs

| Java | Android ABIs |
|---|---|
| 8, 17, 21 | `arm` (ARMv7), `arm64`, `x86`, `x86_64` |
| 25 | `arm` (ARMv7), `arm64`, `x86_64` |

Java 8 uses NDK r10e; Java 17, 21 and 25 use r28c. Exact source pins are
recorded in `build-inputs.json`, and every build writes a per-cell provenance
manifest that is published as `BUILD-MANIFEST.txt`.

## Repository layout

- `toolchains/java8/` — Java 8 recipe: r10e standalone toolchain, bionic port
  patch set, per-ABI build drivers, JRE repack into the launcher's
  `components/jre-8/` layout.
- `toolchains/java17-25/` — Java 17/21/25 recipe: NDK llvm clang toolchain,
  per-version Android patch sets, jlink-based JRE assembly, repack into
  `components/jre-<version>/`.
- `scripts/` — bundle verification, provenance manifests and release checksum
  helpers shared by all cells.

Builds can take hours. See `BUILD-NOTICES.md` for the licensing and
redistribution status of the downloaded inputs.
