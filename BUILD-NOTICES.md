# Build inputs and redistribution notices

This project contains its own version-specific build scripts, Android patch sets, ABI wrappers, and repacking scripts in `toolchains/`. The workflow runs those checked-in files directly.

The build downloads OpenJDK source and the Android NDK, plus native dependencies required by the build scripts. Those inputs remain governed by their own licenses and notices. OpenJDK is generally distributed under GPLv2 with the Classpath Exception, with additional component-specific notices. Preserve all applicable OpenJDK, font, native-library, and patch notices in any redistributed runtime bundle.

The project does not include compiled Java runtimes and does not grant redistribution rights for downloaded build inputs or generated binaries. Review the licenses accompanying each input and output before publishing your release.
