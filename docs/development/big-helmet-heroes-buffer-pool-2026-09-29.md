# Big Helmet Heroes: completed Vulkan buffer reuse — September 29, 2026

This follows the [grouped page-watch change](big-helmet-heroes-page-watches-2026-09-29.md).
A separate 12-second CPU sample of that runner still found repeated driver
allocation work in the tutorial: 108 render-thread samples in
`NtGdiDdDDIDestroyAllocation2` and 73 in `NtGdiDdDDICreateAllocation`.
These counts identify work to investigate; they are not timings or a percentage
of frame cost. Stack scanning associated most destruction samples with the
buffer branch of `destroyVulkanObject`. This diagnostic launch is excluded
from performance comparisons.

## Change and lifetime rules

The shared Vulkan backend now retains completed ordinary buffer allocations in
a bounded pool. The default limit is 32 MiB and 256 buffers, with no individual
allocation above 16 MiB. `PS5_GPU_BUFFER_RECYCLE_MIB=0` disables it; the runner
accepts a maximum of 256 MiB. Capacity is allocated on demand. Live guest buffer
cache capacity remains 4,096 entries.

Reuse requires an exact match of requested size, usage flags, required memory
properties and preferred memory properties. Imported guest memory is excluded.
The existing deferred-destruction timeline decides when an allocation is safe:
a buffer referenced by a recording or queued command cannot enter the pool.
Pool lookup adds no queue submission or GPU wait. CPU mapping state is retained,
and callers initialize contents through their existing upload paths. Reusing an
allocation does not certify guest contents or skip freshness checks.

FIFO replacement frees completed obsolete sizes under byte or entry pressure.
Buffer and image allocation failures can drain the spare pool before retrying;
renderer teardown frees all spares and disables further retention. The new
`[gpu buffer allocations]` profile line reports creation and destruction host
time, reuse counts and the actual spare allocation bytes.

## Validation

All 190 Vulkan module tests pass. The new `vulkan-smoke --buffer-recycle` native
probe records a real GPU copy, retires its source before submission, allocates
and overwrites a second matching buffer, then verifies the original copy.
After completion it verifies reuse of the original handle and allocation.
It also checks mismatched requests, persistent and temporary mapping modes,
byte pressure, the 256-entry cap and oversized rejection.

The same probe passes with the installed Khronos validation layer enabled and
no VUID/validation-error messages. The loader does report pre-existing missing
Steam overlay/Fossilize JSON manifests; those are not validation failures.
Six existing native probes also pass: expanded buffer cache, cache budget,
clean-buffer retention, queued reuse, rename pressure and buffer-view coherence.

## Game measurements

The same ReleaseFast executable is used for all five launches on the Ryzen 7
7700 / RTX 3070 Ti host, PPSA19943, with retained caches, `PS5_HLE_PROFILE=1`,
one copy participant and 4,096 guest buffer-cache entries. Only
`PS5_GPU_BUFFER_RECYCLE_MIB` changes between control (0), default (32), and
the additional tutorial experiment (64). Menu runs last 150 seconds with
controller input; tutorial runs last 180 seconds with isolated scripted input.
No compilation, CPU sampling or screenshot capture overlaps these runs.

Statistics exclude loading frames above one second and the first 60-flip
interval in each scene. These are periodic samples, not continuous FPS averages
or 1% lows. Scripted launches are not identical draw-by-draw replays; startup
and scene progression vary slightly. Loading stalls remain outside this table.

| Scene / spare budget | Median frame | Approximate FPS | Samples | Range |
|---|---:|---:|---:|---:|
| Menu / disabled | 160 ms | 6.25 | 11 | 146–168 ms |
| Menu / 32 MiB | 153 ms | 6.54 | 11 | 144–165 ms |
| Tutorial / disabled | 282 ms | 3.55 | 7 | 274–290 ms |
| Tutorial / 32 MiB | 265 ms | 3.77 | 7 | 259–293 ms |
| Tutorial / 64 MiB experiment | 259.5 ms | 3.85 | 8 | 252–279 ms |

The lower medians are encouraging, but sampled ranges overlap and one pair of
launches does not establish a repeatable whole-game FPS gain. The allocation
counters demonstrate reduced native allocation work independently of that
uncertainty. Medians below use the same accepted frame samples. The combined
time is calculated per frame before taking its median.

| Scene / spare budget | New buffers | Freed buffers | Reuses | Create + free host time |
|---|---:|---:|---:|---:|
| Menu / disabled | 12 | 12 | 0 | 2.950 ms |
| Menu / 32 MiB | 2 | 2 | 9 | 0.412 ms |
| Tutorial / disabled | 135 | 135 | 0 | 28.842 ms |
| Tutorial / 32 MiB | 83 | 82 | 48 | 15.796 ms |
| Tutorial / 64 MiB experiment | 59.5 | 60 | 64 | 11.873 ms |

At the default 32 MiB, tutorial creation/destruction time falls from 28.842 to
15.796 ms, about 45%. This measures those operations, not all pool lookup or
resource-preparation work. The larger experiment reduces them further, but
its frame median improves only from 265 to 259.5 ms with overlapping ranges.
It has no matched menu or other-title measurement, so 32 MiB remains the shared
default. The existing environment setting allows the larger budget explicitly.

The default tutorial still spends a median 250 ms of a 265 ms frame in submission
processing, including 36.2 ms of fence waits across 274 Vulkan submissions.
Uploads remain about 100.9 MiB and readbacks 68.2 MiB per sampled frame.
The compute-buffer preparation scope falls from 32 to 22 ms, while substantial
image preparation and copying remain. Scopes overlap and cannot be added as
independent savings. The guest buffer content cache still evicts about 1,281
ranges per sampled tutorial frame; this allocation pool does not retain their
content identities. 30 FPS has not been reached.

## Capture and local executable

[The new screenshot](../images/big-helmet-heroes-buffer-pool-tutorial.png) is an
unedited 1765×993 capture of the actual game window, taken about
49 seconds after launch following profiled flip 300. It shows the
character, HUD, windmills and Move/Sprint prompts. This separate visual run
uses the default 32 MiB budget and is excluded from the performance tables.
Output is 1920×1080; internal targets can be larger. Visual artifacts remain.
Full playability, save recovery and long-session stability are unverified.

All five measured launches and the separate 150-second visual run continue
advancing frames with no logged command-header guard failures, stopped queues,
guest faults, device loss or panics. The visual run reaches profiled flip
660. The harness ends each process at its deadline. Sampled pool accounting
stays within its byte limit and 256-entry cap in every run. These checks do not
establish long-session stability. The website passes all 56 tests, TypeScript
checking and a production build.

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast at 2026-09-29 14:10:01
(Europe/Minsk), 38,695,936 bytes. SHA-256:

```text
895668CADCE2FA16E3F8DED27FA03EC70ACDDD110ACF149EC9E066842FA30690
```

Raw logs and executable/environment manifests are in
`out/bhh-buffer-pool-menu-off`, `out/bhh-buffer-pool-tutorial-off`,
`out/bhh-buffer-pool-menu-on`, `out/bhh-buffer-pool-tutorial-on`,
`out/bhh-buffer-pool-tutorial-wide` and `out/bhh-buffer-pool-visual-final`.
The preceding-runner CPU diagnostic is in `out/bhh-allocation-cpu-profile`;
build, unit and native probe logs use the `out/bhh-buffer-pool-` prefix.
The public 0.3.2 release download predates these development changes.
