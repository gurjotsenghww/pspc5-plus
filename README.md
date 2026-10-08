<div align="center">
  <img src="assets/branding/ps5pcem-icon-256.png" width="148" height="148" alt="PSPC5 Plus application icon">
  <h1>PSPC5 Plus</h1>
  <p><strong>Open-source PlayStation 5 emulation and compatibility research</strong></p>
  <p>Native guest execution · RDNA2 shader translation · Vulkan rendering · Windows launcher</p>
  <p>
    <img src="https://img.shields.io/badge/platform-Windows%20x64-3b95ff?style=flat-square" alt="Windows x64">
    <img src="https://img.shields.io/badge/Zig-0.16-f7a41d?style=flat-square" alt="Zig 0.16">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-6f7782?style=flat-square" alt="GPL-3.0-or-later"></a>
    <img src="https://img.shields.io/badge/status-active%20development-e6a23c?style=flat-square" alt="Active development">
  </p>
  <p>
    <a href="docs/README.md"><strong>Documentation</strong></a>
    · <a href="docs/compatibility/README.md">Compatibility Database</a>
    · <a href="CHANGELOG.md">Changelog</a>
    · <a href="CONTRIBUTING.md">Contributing</a>
    · <a href="https://github.com/gurjotsenghww/pspc5-plus/issues">Report an issue</a>
  </p>
</div>

> [!IMPORTANT]
> **PSPC5 Plus** is an experimental open-source PlayStation 5 emulator and interoperability research project under active development. A growing number of tested titles reach gameplay, and several are already playable, but compatibility, performance, graphics, audio, and stability vary by title and host hardware. Use only game content and system files that you are legally entitled to use. See the [compatibility database](docs/compatibility/README.md) and [project status](docs/project-status.md).

---

## Origins and Upstream Attribution

**PSPC5 Plus** is derived from the pioneering open-source project [**PS5PCEM**](https://github.com/iStark/PS5PCEM) created by **Artur Strazewicz (iStark)**.

- **Upstream Repository**: [https://github.com/iStark/PS5PCEM](https://github.com/iStark/PS5PCEM)
- **Upstream Author**: Artur Strazewicz (`@iStark`)
- **License**: [GNU General Public License v3.0 or later](LICENSE) (fully preserved)

PSPC5 Plus continues development and research building upon this solid foundation, with enhanced compatibility tracking, regression test automation, shader analysis, performance profiling tools, and community-driven development, while maintaining upstream synchronization capabilities.

---

## Compatibility Summary

| Title | ID | Status | Measured Milestones & Highlights |
|---|---|---|---|
| **Subnautica: Below Zero** | PPSA02457 | **Playable · Completable** | Restores Survival save, renders snowy world and HUD. 10.60 FPS combined (15.5 FPS menu). |
| **Terminator 2D: No Fate** | — | **Playable · Completable** | Completed without reported defects. Correct backgrounds, characters, HUD, textures and colors. |
| **Jets 'n' Guns 2** | — | **Playable · Completable** | Playthrough confirmed. Parallax scrolling, audio routing, levels, HUD and enemies render accurately. |
| **Asterix & Obelix: Slap Them All!** | — | **Playable · Completable** | Playthrough confirmed. 28–31 ms frame times, 3,000-flip stability run verified without rejected submissions. |
| **Cat Quest III** | — | **Playable · Completable** | Playthrough confirmed. Menus, cards, dialogue, island terrain render correctly. |
| **Dreaming Sarah** | — | **Playable · Completable** | Playthrough confirmed. Title menu and first scene run at 60 FPS cap on RTX 3070 Ti. |
| **Quake II (2023)** | PPSA09477 | **Playable · Completable** | Playthrough confirmed. Lighting, textures, weapons, NPCs, controller input, buffer reuse working. |
| **Jurassic Park Classic Games Collection** | — | **Playable · Completable** | Playthrough confirmed. FreeType font rendering and Latin-1 atlas support enabled. |
| **Mighty Morphin Power Rangers: Rita's Rewind** | — | **Playable · Completable** | Playthrough confirmed. Publisher intro, menu, training stage and controller input working. |
| **Grand Theft Auto III: The Definitive Edition** | PPSA03527 | **In-game** | Opening scene renders, walking, car entry and driving verified. Lighting/shadow refinement ongoing. |
| **Little Nightmares Enhanced Edition** | PPSA10737 | **In-game** | Opening room reached, save/reload verified. Dark/reflective material shader improvements ongoing. |
| **Ghost of Yōtei** | — | **Intro / In-engine** | H.264 intro video presented; 3D scenes, post-tree cinematic reached. Active RDNA2 shader and pipeline work ongoing. |

For detailed title reports, engine notes, and screenshots, consult the [Compatibility Database](docs/compatibility/README.md) and [docs/project-status.md](docs/project-status.md).

---

## Architecture Overview

PSPC5 Plus organizes the emulator into modular components:

```
PS5 Title (ELF/SELF)
  ↓
[loader] Maps ELF64 segments, resolves relocations, parses dynamic linkage and TLS
  ↓
[memory] 64 GiB..1008 GiB guest virtual address space management & GPU page generation
  ↓
[cpu] Windows x86-64 native execution bridge & guest thread dispatching
  ↓
[hle] High-level emulation (kernel, libc, sync, pthreads, savedata, audio, video codecs)
  ↓
[gpu] Stateful AGC command-stream decoder, DCB/ACB dispatch, context state machine
  ↓
[rdna2] RDNA2 ISA decoder, control-flow graph builder, SSA/IR, and SPIR-V emitter
  ↓
[vulkan] Dynamic Vulkan backend, pipeline compiler, image alias tracking, timeline sync
  ↓
[window] / [input] Win32 surface presentation, DualSense HID / XInput controller polling
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for complete subsystem documentation.

---

## Building and Running

### Prerequisites

- **OS**: Windows 10 (2004+) or Windows 11 x64
- **CPU**: x86-64-v3 baseline (AVX2, BMI2, FMA)
- **GPU**: Vulkan 1.2+ capable GPU (Vulkan 1.3/1.4 recommended; NVIDIA RTX / AMD RDNA / Intel Arc)
- **Compiler**: [Zig 0.16.0](https://ziglang.org)

### Build Commands

```sh
# Verify module compilation
zig build check

# Run the complete test suite
zig build test

# Build the native Windows launcher (zig-out/bin/pspc5-plus.exe)
zig build build-launcher

# Build the standalone title runner (zig-out/bin/game-run.exe)
zig build build-game-run

# Run the RDNA2 shader disassembler
zig build run -- shader.bin

# Run the headless Vulkan compute/staging probe
zig build vulkan-smoke
```

---

## Quick Start

1. Build or download PSPC5 Plus.
2. Launch `pspc5-plus.exe`.
3. Select a folder containing a decrypted PS5 title you legally own.
4. Click **Launch game**.

---

## Documentation Index

| Resource | Contents |
|---|---|
| [Documentation Index](docs/README.md) | Complete directory of architecture, development, and user guides |
| [Compatibility Database](docs/compatibility/README.md) | Structured compatibility entries and title profiles |
| [Building and CLI Guide](docs/getting-started.md) | Command-line tools, debugging switches, and library usage |
| [Implementation Status](docs/implementation-status.md) | Subsystem-by-subsystem breakdown of implemented functionality |
| [Architecture Reference](docs/architecture/overview.md) | CPU, Loader, HLE, GPU, RDNA2, Vulkan, and Memory internals |
| [Contributing Guidelines](CONTRIBUTING.md) | Development standards, Git conventions, and PR requirements |
| [Changelog](CHANGELOG.md) | Version history, added features, fixes, and improvements |
| [Legal Boundaries](docs/legal.md) | Licensing, fair-use research scope, and legal compliance |

---

## Legal and Ethical Policy

PSPC5 Plus is an independent interoperability and computer science research project.

- PSPC5 Plus contains **NO copyrighted game assets**, proprietary ROMs, leaked Sony console firmware, or cryptographic keys.
- PSPC5 Plus does not include or provide DRM circumvention mechanisms designed for piracy.
- Users must provide their own legally obtained software and decryption keys for interoperability testing.
- Licensed under the [GNU General Public License v3.0 or later](LICENSE).
