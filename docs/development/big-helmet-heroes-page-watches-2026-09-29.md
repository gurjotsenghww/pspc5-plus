# Big Helmet Heroes: grouped GPU page watches — September 29, 2026

This follows the [buffer-cache recency change](big-helmet-heroes-buffer-recency-2026-09-29.md).
A separate CPU sample of the current tutorial found repeated native protection
changes in `trackGpuRead` and `notifyGuestWrite`, alongside copies, allocation
work and GPU waits. This diagnostic run is excluded from FPS comparisons.

The Windows memory tracker now groups eligible adjacent 16 KiB pages within a
64 KiB direct-memory granule. It uses a fresh native-region query to stop at
view and protection boundaries. The memory mappings themselves keep their
existing sizes. Private and unaligned mappings retain individual page operations.
The change applies across titles, without a game identifier condition.

## Correctness boundaries

Windows requires a protection range to remain inside the same reserved region;
view protection must also be compatible with the mapped access. See
[Microsoft's VirtualProtect documentation](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualprotect).
The tracker therefore queries the current region before each eligible group,
including after unmapping and remapping at the same address.

All entries for a group are allocated before changing its host permissions.
Only a successfully protected range is marked armed. Native write-fault handlers
share the tracker lock, so they cannot observe half-published group metadata.
Generations remain per page; a native fault restores only its own page.
HLE writes combine restoration only where saved logical rights agree. A failed
grouped protection retries one page without certifying the remainder.

All 25 memory tests pass in ReleaseSafe, including three new native Windows
cases for group boundaries, per-page epochs, native faults, mixed read/write/
execute rights, remapped small views and a deliberately rejected grouped
operation. All 541 HLE tests also pass.

## Isolated operation cost

A ReleaseFast executable contains the previous memory tracker from commit
`3acc9fe` and the changed tracker. It alternates old/new/new/old twice. Each
interval creates its address space outside the timed region, warms four cycles,
then measures 64 observation/write-notification cycles. A real native store
follows each notification; generation and content checks follow timing.
Games and other compilers do not overlap this benchmark. Results are medians
of four intervals per implementation on the Ryzen 7 7700.

| Mapping / range | Before | After | Protection calls per cycle, before / after |
|---|---:|---:|---:|
| Aligned direct memory, 8 MiB | 0.4202 ms | 0.2788 ms | 1024 / 256 |
| Unaligned direct memory, 1 MiB | 0.0540 ms | 0.0544 ms | 128 / 128 |
| Private memory, 1 MiB | 0.0508 ms | 0.0509 ms | 128 / 128 |

The aligned cycle is about 34% cheaper. The new path also performs native-region
queries; the call column counts protection attempts only. Their overhead is
included in the measured time. Old call counts follow the per-page loop;
new counts come from the tracker counter. This is an operation-level result, not a game
FPS multiplier. The small-mapping results are essentially unchanged.

## Game measurements

The control is the previous recency runner, SHA-256
`C6278D1F66FE778650EE2C5401485A1D20FC5583025C2FCBBB41D61712C77DBE`.
Both builds use PPSA19943, the Ryzen 7 7700 and RTX 3070 Ti, ReleaseFast,
`PS5_HLE_PROFILE=1`, one copy participant and 4,096 buffer-cache entries.
Menu launches last 150 seconds with controller input; tutorial launches last
180 seconds with isolated scripted input. Working directory and retained
caches are shared. Compilation, CPU sampling and screenshot capture do not
overlap these performance runs.

Statistics exclude loading frames over one second and the first 60-flip
interval in each scene. These are periodic frame samples, not continuous
averages or 1% lows.

| Scene / build | Median frame | Approximate FPS | Samples | Range |
|---|---:|---:|---:|---:|
| Menu, control | 161 ms | 6.21 | 9 | 154–176 ms |
| Menu, new | 153 ms | 6.54 | 11 | 146–170 ms |
| Tutorial, control | 285 ms | 3.51 | 7 | 273–293 ms |
| Tutorial, new | 277 ms | 3.61 | 8 | 268–287 ms |

The sampled ranges overlap. These limited runs do not establish a repeatable
whole-game FPS gain. The isolated watch-operation gain does not remove
resource copies, allocation work or GPU dependencies.

The new tutorial samples still spend 261 ms of a 277 ms frame inside
submission processing, including about 36.0 ms of fence waits. Medians are
286.5 Vulkan submissions, 105.9 MiB uploaded and 63.8 MiB read back per
sampled frame. Timing scopes overlap. Resource preparation, copies, allocation
work and synchronization remain substantial costs. 30 FPS has not been reached.

The compute-image preparation scope decreases from 48 to 44 ms in the menu
and from 47 to 40 ms in the tutorial. Tutorial fence waits remain about 36 ms.
These scopes overlap the frame timings and are not additive savings. The
previous report also sampled the preceding runner at 277 ms in the tutorial;
the current comparison therefore does not establish a lasting tutorial gain.

## Capture and local executable

[The new screenshot](../images/big-helmet-heroes-page-watches-tutorial.png) is an
unedited 1765×993 capture of the actual game window, taken about
64 seconds after launch following profiled flip 240. It shows the
character, HUD, windmills and Move/Sprint prompts. This separate visual run
is excluded from the performance table. Output is 1920×1080, with potentially
larger internal targets. Visual artifacts remain; full playability and
long-session stability are unverified.
All four matched launches and the separate 150-second visual run continue
advancing frames without logged command-header guard failures, stopped queues,
guest faults, device loss or panics. The visual run reaches profiled flip
540. The harness ends each process at its time limit. This limited check
does not establish long-session stability.

The website passes all 56 tests, TypeScript checking and a production build.

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast at 2026-09-29 13:35:27
(Europe/Minsk), 38,671,360 bytes. SHA-256:

```text
6E1AED8225CFFB102486BB334795B25AC046E9AFC2EBFB5E88C5BB90E3822A88
```

Local manifests and raw logs are in `out/bhh-prep-menu-control`,
`out/bhh-prep-tutorial-control`, `out/bhh-prep-menu-final`,
`out/bhh-prep-tutorial-final` and `out/bhh-prep-visual-final`.
The separate CPU diagnostic is in `out/bhh-prep-cpu-profile`; native benchmark
results and checks are in `out/bhh-prep-watch-bench.log`,
`out/bhh-prep-memory-tests.log` and `out/bhh-prep-hle-tests.log`.
The public 0.3.2 release download predates these development changes.
