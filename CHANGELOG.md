# Changelog

All notable changes to the **PSPC5 Plus** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] - development

### Added
- **PSPC5 Plus Identity & Repository Structure**: Fork established from upstream `iStark/PS5PCEM` (commit `7b9cc37`).
- **Structured Compatibility Database**: Created machine-readable database in `docs/compatibility/database.json` and human-readable index in `docs/compatibility/README.md`.
- **Automated CI Workflows**: GitHub Actions workflows for continuous compilation (`build.yml`), unit tests (`tests.yml`), regression checks (`regression.yml`), and automated release packaging (`release.yml`).
- **Developer Tooling Infrastructure**: Initial tooling directory structure under `tools/` covering profiler, shader analysis, trace viewing, and compatibility validation.

### Changed
- **Launcher Branding**: Updated Windows desktop launcher window titles, dialogs, and resource definitions to reflect PSPC5 Plus while honoring upstream author Artur Strazewicz.
- **Build Configuration**: Configured `build.zig` and `build.zig.zon` with package identifier `pspc5-plus` and artifact target `pspc5-plus.exe`.

---

## [0.3.3] - Upstream Base

### Features Inherited from Upstream PS5PCEM v0.3.3:
- Kernel `MemoryPool` allocation and batch mapping operations.
- FreeType font rendering with Latin-1 atlas support.
- Packed 11/11/10 UNORM color blending through storage-buffer copies.
- RDNA2 DS atomic operations (`DS_INC`, `DS_DEC`, `DS_MSKOR`), D16_HI half-word accesses, and `DS_PERMUTE`/`DS_BPERMUTE`.
- Dynamic Vulkan VideoOut presentation with timeline semaphores and image alias coherency.
- Native x86-64 Windows guest execution bridge, thread bootstrapping, and SEH contained-fault attribution.
- Sony DualSense and DualShock 4 direct HID support alongside XInput fallbacks.
- FFmpeg H.264/AAC media playback via `libSceVideodec2`.
