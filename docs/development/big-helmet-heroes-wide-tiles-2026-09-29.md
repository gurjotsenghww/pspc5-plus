# Big Helmet Heroes: wider CPU tile copies — September 29, 2026

This follows the [command-queue and storage-coherence fixes](big-helmet-heroes-storage-coherence-2026-09-28.md).
The shared GPU layout converter now copies a complete 16-byte horizontal run
when its address equation proves those bytes are contiguous. Previously it
copied each pixel separately, including common four-byte color formats.
The change applies to both tiling and detiling across titles; it has no
Big Helmet Heroes identifier or shader-signature condition.

## Correctness boundaries

The converter checks the actual X-offset table once per layout conversion.
Every eligible group must start at a logical 16-byte boundary and contain
consecutive element addresses. Each row must also have an XOR mask that
preserves the low four address bits. Only then can it copy 16 bytes together.
This does not require the host allocation itself to be SIMD aligned.

Clipped right edges and noncontiguous swizzles retain the element loop.
The existing slice offsets, macro-block XOR, pitch, padding and worker ownership
are preserved. Linear images retain row copies, and existing 16-byte elements
already use a full-width copy. The worker-count policy is unchanged: one for
Big Helmet Heroes by default, with the existing `PS5_GPU_COPY_WORKERS` override.

All 236 GPU unit tests pass. The added test independently calculates every
element address for one-, two-, four-, eight- and sixteen-byte elements across
linear, standard, partially resident, depth and render-target layouts where
supported. It compares the entire tiled allocation, including untouched
padding, and detiles the independently constructed reference. Cases include
unaligned host buffers, clipped blocks and a nonzero first array slice.
Existing parallel-copy tests compare one and four participants.

Real-device probes also pass:

- `--storage-cpu-reuse`: CPU replacement, deferred GPU writes, padding and rebinding.
- `--layered-volume`: 32 layers, ancillary input, full raster coverage and 3D swizzling.
- `--queued-detile`: 70 textures, descriptor reuse, mip levels, rebased views,
  updates, bounds checks and agreement between CPU and GPU conversion paths.

## Isolated conversion cost

On the Ryzen 7 7700, an isolated ReleaseFast executable contains both the
previous converter from commit `e9d73f4` and the new one. It alternates
old/new/new/old twice, with one copy participant. Each interval warms the
buffers, times eight tiling calls and eight detiling calls separately, and
verifies restored contents outside the timed region. The table gives median
milliseconds per conversion across four intervals per implementation.
Games, other GPU probes and compilers are stopped during this measurement.

| Layout | Bytes/element | Extent | Tile before / after | Detile before / after |
|---|---:|---|---:|---:|
| Standard 64 KiB | 4 | 1920×1080 | 0.708 / 0.284 ms | 0.705 / 0.294 ms |
| Standard 64 KiB | 4 | 3840×2160 | 6.233 / 4.142 ms | 6.308 / 3.902 ms |
| Render target | 4 | 1920×1080 | 0.776 / 0.306 ms | 0.723 / 0.326 ms |
| Render target | 4 | 3840×2160 | 6.994 / 4.341 ms | 6.944 / 4.291 ms |
| Standard 64 KiB | 8 | 1920×1080 | 2.033 / 1.732 ms | 2.120 / 1.636 ms |
| Standard 64 KiB | 8 | 3840×2160 | 10.146 / 8.465 ms | 9.720 / 8.274 ms |
| Render target | 8 | 1920×1080 | 2.324 / 1.748 ms | 2.373 / 1.758 ms |
| Render target | 8 | 3840×2160 | 11.686 / 9.124 ms | 11.496 / 9.142 ms |

These are repeated CPU-buffer conversion costs, not game FPS multipliers.
The buffers are reused; cache behavior differs from a complete game frame.

## Game measurements

Game measurements use PPSA19943, Ryzen 7 7700, RTX 3070 Ti and ReleaseFast.
Every comparison launch lasts 150 seconds, uses `PS5_HLE_PROFILE=1`, the same
working directory and retained caches. Menu checks select controller input;
tutorial checks use automatic input. Builds, device probes, captures and the
isolated CPU benchmark do not overlap the game performance runs.

Statistics retain the previous report's filter: exclude loading frames over
one second and the first 60-flip interval in each scene. These are medians of
periodic frame samples, not continuous averages or 1% lows. The control is
the preceding command-span/coherence runner, SHA-256
`C7108D992475F21C328EDCA6D854A69885096866B1B09F61D5834141B8D2D1FB`.

| Scene / build | Copy participants | Median frame | Approximate FPS | Samples | Range |
|---|---:|---:|---:|---:|---:|
| Menu, control before build | 1 | 168 ms | 5.95 | 11 | 163–176 ms |
| Menu, new | 1 | 160 ms | 6.25 | 11 | 156–167 ms |
| Menu, control repeated afterwards | 1 | 171 ms | 5.85 | 9 | 165–181 ms |
| Menu, control with extra workers | 4 | 151.5 ms | 6.60 | 12 | 147–159 ms |
| Menu, new with extra workers | 4 | 152 ms | 6.58 | 12 | 146–171 ms |
| Tutorial, new (completed early-morning check) | 1 | 280 ms | 3.57 | 4 | 275–286 ms |

The single-participant menu median improves by roughly 5–6% in frame time
against the two controls, but the sampled ranges overlap. This is a modest
result on this host, not a guaranteed gain for every title. Upload plus
readback traffic remains about 122 MiB per menu frame. The split changes
between runs, so the change in readback bytes alone is not a traffic reduction.

Four participants reduce compute-image preparation from about 51 to 43 ms
in the new build. However, their whole-frame result is essentially unchanged
from the old four-participant control. This does not establish an additional
game FPS gain for wide copies with four workers, or justify changing every
title's default worker count. `PS5_GPU_COPY_WORKERS=4` remains an opt-in setting.

The tutorial result does not establish an FPS improvement. Its first control
was interrupted. After work resumed, both 150-second checks moved into a
different scene: the control retained only one initial-tutorial sample after
warm-up, and the new build retained none. Those checks are excluded from the
FPS comparison. Automatic input also accepts host input; it is not a locked
input replay. The completed early-morning tutorial check remains the reported
measurement. **30 FPS has not been reached.**

In that completed check, the new build spends about 265 ms of a 280 ms frame
inside submission processing, with roughly 38 ms of fence waits, 265 Vulkan
submissions, 100 MiB uploaded and 68 MiB read back. The buffer cache still
evicts about 1,260 entries per sampled frame. These timing scopes overlap.
Large loading stalls also remain: the resumed run includes a 50,811 ms frame,
which is excluded from the steady-scene statistics.

Wider CPU copies do not remove those transfers or dependencies. A larger gain
requires keeping compatible producer/consumer resource transitions on the GPU,
reducing cache churn and avoiding host waits where dependencies permit it.
Reusing an image solely because its guest address matches would be incorrect
when the format, extent or guest contents differ.

## Repeat launches and capture

All completed performance launches continue advancing frames without logged
command-header guard failures, stopped queues, guest faults, device loss or
panics. Each process is ended by the harness at its time limit. This does not
establish long-session stability or full playability.

[The new tutorial screenshot](../images/big-helmet-heroes-wide-tiles-tutorial.png)
is an unedited 1765×993 capture of the actual game window from the final runner.
It shows the character, HUD, windmills and Move/Sprint prompts. The visual
harness waits for a completed tutorial frame before capturing: this image was
taken about 69 seconds after launch, following profiled flip 300. An earlier
capture at a fixed 75 seconds landed on a loading screen and is not published
as a tutorial image. Neither visual run contributes to the performance table.
Output is 1920×1080, while internal targets can be larger. Rendering artifacts
remain.
The final visual run lasts 150 seconds and advances through profiled flip 540,
with no logged stopped queues, guest faults, device loss or panics.

Local manifests, hashes and logs are retained under `out/bhh-copy-menu-control`,
`out/bhh-copy-menu-four`, `out/bhh-wide-menu-new`,
`out/bhh-wide-menu-old-repeat`, `out/bhh-wide-menu-four`,
`out/bhh-wide-tutorial-new`, `out/bhh-wide-tutorial-old-resumed` and
`out/bhh-wide-tutorial-new-resumed`. The incomplete original tutorial control
is retained separately in `out/bhh-wide-tutorial-old`.
CPU conversion results are in `out/bhh-wide-cpu-bench.log` and its summary JSON.
The final image and capture metadata are in `out/bhh-wide-visual-final`.

## Local executable

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast on September 29, 2026
at 02:32:20 (Europe/Minsk), 38,440,448 bytes. SHA-256:

```text
71FB1C1670C110F07AA7C80A0B9B832B0C6DD6D64218C1EC20FC6E9C5BE719D4
```

The public 0.3.2 release download predates this development build.
