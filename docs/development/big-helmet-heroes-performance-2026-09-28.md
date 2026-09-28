# Big Helmet Heroes performance investigation — September 28, 2026

The main cost after startup is the host graphics backend: resource preparation,
copies between guest memory and Vulkan resources, and synchronization. The
stable menu does not repeatedly compile its pipelines. Entering the tutorial
adds roughly four times as many draws and substantially more buffer-cache churn.
This work does not establish 30 FPS or complete gameplay compatibility.

## Measurement conditions

PPSA19943 ran on a Ryzen 7 7700 and NVIDIA GeForce RTX 3070 Ti using ReleaseFast.
Output remained 1920×1080, with a 1765×993 client window on this desktop. Internal
rendering is still controlled by the game: traced resources include 3840×2160
depth and 2848×1600 intermediate targets. Output size alone does not reduce those
passes to 1080p.

The existing game, save files, shader catalog and Vulkan pipeline cache were
retained. Page tracking stayed enabled. Menu runs used
`PS5_INPUT_MODE=controller`; tutorial runs used the default automatic input.
`PS5_HLE_PROFILE=1` was enabled for the reported baseline/final comparisons.
Each comparison launch lasted 150 seconds. The tutorial comparison used the
saved pre-change executable, followed by the final executable, with no builds
or GPU probes running alongside either measurement.

Frame figures below are medians of periodic frame samples, not a continuous
average or a 1% low. Loading frames and the first sampled 60-flip interval of
each rendered scene are excluded. Screenshots confirm the scene actually
rendered; advancing flip counters alone are insufficient.

## Results

| Scene | Before | After | Periodic samples before / after |
|---|---:|---:|---:|
| Main menu | 176 ms / 5.68 FPS | 168.5 ms / 5.93 FPS | 10 / 10 |
| Tutorial, initial stable samples | 288 ms / 3.47 FPS | 284 ms / 3.52 FPS | 3 / 3 |

Menu samples ranged from 167–187 ms before and 162–179 ms after. The observed
median improvement is about 4.3% in frame time, with overlapping ranges; this is
a small reduction, not evidence of a large or universal FPS improvement.
Tutorial ranges were 282–293 ms before and 282–304 ms after, with 116 dispatches
per sampled frame and about 950–970 draws. That difference does not establish
a meaningful tutorial FPS gain. The new path removes the redundant budget sums,
but synchronization, image staging and remaining table walks still dominate.

The final tutorial also encountered 2,104 ms and 3,574 ms frames when new effects
appeared. Graphics/compute pipeline misses cost 319 + 1,449 ms in the first and
1,893 + 1,273 ms in the second. These are first-use pipeline-creation stalls,
distinct from the steady renderer cost. The initial world transition took
25,017 ms: 4,374 ms inside submission processing and 20,643 ms outside it. The
latter is not all shader compilation and needs a separate loading-thread profile.

## Costs and the change

A baseline menu sample uses about 244 draws, 72 dispatches and 194 Vulkan
submissions. Approximately 52 MiB is uploaded and 70 MiB read back per frame;
sampled fence waits consume about 32 ms. The renderer accounts for about 161 ms
of a 176 ms frame, leaving about 14 ms outside submission processing.

The tutorial initially showed about 930–950 draws, 110 dispatches and
1,170 buffer-cache evictions per frame. Its 4,096 entries occupied only about
350–380 MiB, below the 4 GiB backing budget. A trial of 8,192 entries still filled
up and continued evicting about 220–230 entries per menu frame. Merely doubling
the entry limit did not solve the stream of new ranges; the original limit is
retained.

Every cache miss previously rescanned all retained buffers to calculate the
backing budget. Device-placement decisions performed another full sum when
eligible. At 1,170 misses and 4,096 entries, the first sum alone visits roughly
4.8 million entries per tutorial frame, even while comfortably below budget.

The renderer now maintains the total backing capacity and device-local capacity
when an allocation is added, replaced, trimmed or renamed. Budget checks use
those totals. Capacity includes transfer mirrors and oversized recycled buffers,
just as before. Retired rename allocations retain their separate budget and
lifetime tracking. This change applies to the shared Vulkan backend without a
title-specific condition. Cache limits, invalidation, GPU waits and drawing
commands are unchanged.

## Remaining work

- Keep more render-target/storage-image producer and consumer transitions on
  the GPU. Repeated materialization still copies and converts tens of MiB back
  into guest memory, then stages some of it again.
- Reduce command-buffer submissions and waits where dependency tracking proves
  they can stay ordered on the queue. Dropping waits without preserving those
  dependencies can reuse unfinished resources.
- Reduce per-draw descriptor/scalar preparation and the remaining cache-victim
  scans. Buffer accounting removes two sums, not all resource-table traversal.
- Treat scene-loading spikes separately. One observed tutorial transition
  issued over 4,100 dispatches and 5,600 Vulkan submissions in a single frame.
  Steady-state pipeline misses were zero in representative menu/tutorial samples.
  Improve warmup coverage for newly encountered effects rather than interpreting
  all low-FPS frames as repeated compilation of an already cached shader.

Profiler scopes overlap: draw/dispatch/resource times and fence waits must not
be added as independent pieces of frame time. `resident_kib` is a cumulative
resource-reuse counter for the frame, not actual VRAM occupancy.

## Validation

- 187/187 Vulkan unit tests pass.
- Real-device probes cover cache byte pressure, queued buffer reuse, rename-pool
  pressure, device/host uploads, differently sized views and shrinking an 8 MiB
  backing to a four-byte range. They independently sum the retained allocations
  and check the maintained accounting after exercising these transitions.
- The final runner completed a 150-second menu run, a 150-second tutorial
  comparison and a separate 100-second tutorial visual check without logged
  guest faults or device loss. The window-capture helper found no visible window
  at the late capture point in the tutorial comparison; the separate run supplied
  the inspected tutorial screenshot. This does not establish long-session stability.

[Menu screenshot](../images/big-helmet-heroes-performance-menu.png) ·
[Tutorial screenshot](../images/big-helmet-heroes-performance-tutorial.png).
Both are unedited captures of the actual game window, taken using the final runner.

Local evidence is retained in `out/bhh-perf-menu-baseline`,
`out/bhh-perf-menu-final`, `out/bhh-perf-tutorial-control`,
`out/bhh-perf-tutorial-final` and `out/bhh-perf-tutorial-visual`. Each launch
manifest records its executable hash, working directory and environment.

The final local runner is `zig-out/bin/game-run.exe`, built at 20:55:49
(Europe/Minsk), 38,429,184 bytes. SHA-256:

```text
29155C35D0352DABA86FF3EF11A0FDD88EAD1307B225AB5D323BEC5AE15FA0A4
```

The public 0.3.2 download predates this development change.
