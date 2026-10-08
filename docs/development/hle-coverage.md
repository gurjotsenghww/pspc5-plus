# PS5 HLE Library Coverage Matrix

This document tracks the implementation coverage of PlayStation 5 firmware libraries in **PSPC5 Plus**.

---

## Firmware Library Implementation Status

| Library | Status | Implemented Functionality | Stubs / Incomplete | Test Suite |
|---|---|---|---|---|
| **`libkernel`** | **Comprehensive** | Memory allocation, `MemoryPool` batch mappings, direct virtual memory mapping, pthread bootstrap, thread scheduling, futex synchronization, timers, monotonic clocks, TLS template bootstrapping, SEH fault handling. | Some POSIX file flags, exotic ioctl calls. | 120+ unit tests |
| **`libSceVideoOut`** | **Complete** | Port open/close, display mode queries, colorimetry and format negotiation, presentation queue registration, vsync synchronization. | HDR10+ dynamic metadata passthrough. | 18 unit tests |
| **`libSceAudioOut`** | **Complete** | Host WASAPI/direct audio device mapping, multi-port routing, volume/pan control, master bus routing, audio thread scheduling. | 7.1 surround virtualization. | 24 unit tests |
| **`libSceAjm`** | **Complete** | Audio codec registry, MP3/AAC/Opus decoding via bundled codecs, asynchronous audio contexts, batch job queues. | ATRAC9 hardware stream filters. | 32 unit tests |
| **`libSceNgs2`** | **Complete** | Sound voice synthesizer, PCM grain rendering @ 48kHz, channel routing, voice looping, parameter modulation. | Custom DSP effects graphs. | 15 unit tests |
| **`libSceFont`** | **Complete** | FreeType 2.14 static integration, TTF/OTF outline rendering, glyph metrics, clipping, slant, kerning, `.notdef` fallback for Latin-1/Unicode coverage, bounded font cache. | Bidi complex shaping for RTL scripts in guest canvas. | 12 unit tests |
| **`libSceSaveData`** | **Complete** | Per-title save directory mounting under `savedata/<titleId>/<slot>/`, directory sanitization, backup recovery, block-based `sce_sdmemory` synchronization. | Cloud save quota simulation. | 28 unit tests |
| **`libScePad`** | **Comprehensive** | Sony DualSense & DualShock 4 HID reading over USB/Bluetooth, XInput fallback, keyboard remapping profiles, stick deadzones. | Adaptive trigger motorized feedback, haptic waveforms. | 14 unit tests |
| **`libSceVideodec2`** | **Complete** | Windows Media Foundation hardware H.264 decoding, Annex B NAL unit parsing, NV12 to RGB BT.709 presentation frames. | HEVC/H.265 secondary decoder. | 10 unit tests |
| **`libSceSysmodule`** | **Complete** | Dynamic module load requests, dependency graph resolution, reference counting. | None critical. | 8 unit tests |
| **`libSceNet`** | **Partial / Stub** | Local socket emulation, loopback addresses, network configuration stubs. | Full online PSN multiplayer stack. | 6 unit tests |
| **`libSceUserService`**| **Complete** | User ID enumeration, active user query, user profile data simulation. | Multiple concurrent active users. | 8 unit tests |

---

## Coverage Summary & Priorities

- **Total Implemented Functions**: ~560+ symbols registered across guest modules.
- **HLE Test Status**: 569/569 HLE tests passing (`zig build test-hle`).
- **High-Value Targets for Future Work**:
  1. Advanced DualSense haptic motor feedback and trigger profiles in `libScePad`.
  2. HEVC (H.265) video decoding pipeline in `libSceVideodec2`.
  3. Extended async POSIX I/O ring buffers in `libkernel`.
