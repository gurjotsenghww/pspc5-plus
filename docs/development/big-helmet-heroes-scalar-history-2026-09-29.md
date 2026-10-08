# Big Helmet Heroes: scalar load bookkeeping — September 29, 2026

This follows the [completed-buffer pool change](big-helmet-heroes-buffer-pool-2026-09-29.md).
A fresh 12-second CPU sample of that runner still found substantial scalar
execution alongside copies, allocation work and GPU waits. The previous
measured tutorial also spent about 18 ms preparing resource checkpoints over
roughly 4,000 calls per sampled frame. The diagnostic launch is excluded from
FPS comparisons.

## Shared implementation change

Checkpoint consumers use register snapshots and the instruction count, but do
not consume the scalar-load history used for shader specialization. Their pool
now invokes a snapshot mode of the existing evaluator. It performs the same
checked reads, register updates, branches, loop handling and failure recovery,
without building or deduplicating unused load records. This applies to serial
and worker preparation paths and has no title identifier condition.

Full scalar evaluation still retains its load history. A high-water mark of
recorded instruction PCs avoids searching that history on a first forward
visit. Backward or repeated visits keep the existing full comparison, so changed
addresses, values and provenance remain distinct. Evaluation copies carry the
mark and resets clear it. Removing loop records can leave a conservatively high
mark, causing an extra search without weakening duplicate detection.

## Correctness checks

All 237 GPU tests pass in ReleaseSafe. Eleven existing checkpoint regressions
now also compare full and snapshot modes: snapshots, final registers, ordered
read digests and counts, stop reasons, failure state and user-data dependencies.
They include skipped blocks, backward visits, varying and masked loops, failed
loads, late resources and explicit instruction budgets. A new history regression
checks out-of-order PCs, copied evaluations, changed values and resets.

Seven native Vulkan probe commands pass: distinct scalar loads, scalar loops,
counted image loops, uniform/masked image loops, scalar pointers, unbound
snapshots and resource workers. The distinct-load probe preserves 320 loads
through reused SGPRs and changes input data while reusing one pipeline. Worker
checks cover serial, fixed worker counts and adaptive preparation with matching
pixels, changed textures/scalars and descriptor register lifetimes.

## Isolated evaluator measurements

One ReleaseFast x86-64-v3 executable contains the preceding scalar evaluator
from commit `d38d165` and the new evaluator. It alternates old/new/new/old twice
for each workload. Each interval warms 20 walks and measures 20,000 walks for
short fixtures or 2,000 for longer fixtures, with allocations outside the timed
region. The fixtures use 4, 16, 64 or 256 distinct
four-dword scalar loads, overwrite the same SGPR window, and change input bytes
between iterations. Termination, read counts, record counts, PC order and
matching checksums are checked.
Snapshot cases capture all 128 SGPR values before every load. No game or other
compiler overlaps this benchmark. Values are medians of four intervals.

| Mode / scalar loads | Before | After |
|---|---:|---:|
| Full / 4 | 2.368 µs | 2.361 µs |
| Full / 16 | 2.744 µs | 2.679 µs |
| Full / 64 | 4.534 µs | 4.108 µs |
| Full / 256 | 16.093 µs | 8.861 µs |
| Snapshots / 4 | 2.799 µs | 2.779 µs |
| Snapshots / 16 | 3.729 µs | 3.595 µs |
| Snapshots / 64 | 8.070 µs | 6.891 µs |
| Snapshots / 256 | 29.683 µs | 20.206 µs |

Short walks are effectively unchanged. The 64-load fixtures are about 9–15%
cheaper; the 256-load fixtures are about 32–45% cheaper. These synthetic cases
isolate scalar-load bookkeeping and do not represent complete game frames.
The earlier narrower benchmark and this expanded check are both retained in
local logs. The extra short fixtures were checked after the game runs ended;
no compilation or profiling overlaps their timed execution.

## Game measurements

Both builds use PPSA19943 on the Ryzen 7 7700 / RTX 3070 Ti host, ReleaseFast,
retained caches, `PS5_HLE_PROFILE=1`, one copy participant, 4,096 guest-buffer
entries and the same 32 MiB completed-buffer pool. The control is the preceding
`d38d165` runner, SHA-256
`895668CADCE2FA16E3F8DED27FA03EC70ACDDD110ACF149EC9E066842FA30690`.
Menu runs last 150 seconds with controller input; tutorial runs last 180 seconds
with isolated scripted input. Compilation, CPU sampling and screenshot capture
do not overlap the performance launches.

Statistics exclude loading frames above one second and the first 60-flip
interval in each scene. These are periodic samples, not continuous averages
or 1% lows. Scripted input does not produce an identical draw-by-draw replay;
startup and scene progression vary between launches.

| Scene / build | Median frame | Approximate FPS | Samples | Range |
|---|---:|---:|---:|---:|
| Menu / control | 154.5 ms | 6.47 | 10 | 148–164 ms |
| Menu / new | 157 ms | 6.37 | 11 | 148–194 ms |
| Tutorial / control | 269 ms | 3.72 | 9 | 245–282 ms |
| Tutorial / new | 270 ms | 3.70 | 8 | 259–282 ms |

**No game FPS improvement is demonstrated.** The new menu median is slightly
slower and the tutorial median is essentially unchanged. Ranges overlap.
The isolated improvement remains useful for longer scalar-load sequences,
but it does not materially change the measured Big Helmet Heroes frame cost.

Checkpoint preparation medians are 5.178 → 5.163 ms in the menu and
18.523 → 18.279 ms in the tutorial. These small differences are not a robust
whole-game gain; the tutorial also performs slightly fewer checkpoint calls
(4,099 → 4,038) and draws (1,006 → 991) in its median sample. Rounded scalar
provenance timing remains 4 ms in the menu and 12 ms in the tutorial.

The new tutorial still spends a median 255.5 ms of a 270 ms frame inside
submission processing. It has about 31.4 ms of GPU fence waits across 282.5
Vulkan submissions, uploads about 105.9 MiB and reads back 63.9 MiB per sampled
frame. These scopes overlap. Copying, image preparation, synchronization and
remaining allocation work dominate the overall result. 30 FPS has not been
reached. The previous buffer-pool and memory-tracking changes remain enabled.

## Capture and local executable

[The new screenshot](../images/big-helmet-heroes-scalar-history-tutorial.png)
is an unedited 1765×993 capture of the actual game window, taken about 67 seconds
after launch following profiled flip 300. It shows the HUD, windmills,
Move/Sprint prompts and a blue circular effect. The separate 150-second visual
run uses the default 32 MiB buffer pool and is excluded from the performance
tables. Output is 1920×1080; internal targets can be larger. Visual artifacts
remain. Full playability, save recovery and long-session stability are unverified.

All four measured launches and the separate visual run continue advancing
frames with no logged command-header guard failures, stopped queues, guest
faults, device loss or panics. The visual run reaches profiled flip 600.
The harness ends each process at its deadline. These checks do not establish
long-session stability. The website passes all 56 tests, TypeScript checking
and a production build.

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast at 2026-09-29 14:49:33
(Europe/Minsk), 38,695,936 bytes. SHA-256:

```text
5378AADD43CB2A4055887A2716517A0185EBAD1FE717E76D8EFEE1BC0DBFBAD0
```

Raw logs and executable/environment manifests are in
`out/bhh-scalar-history-menu-control`, `out/bhh-scalar-history-menu-final`,
`out/bhh-scalar-history-tutorial-control`,
`out/bhh-scalar-history-tutorial-final` and
`out/bhh-scalar-history-visual-final`. The preceding-runner CPU diagnostic
is in `out/bhh-resource-cpu-profile`. Build, unit, native probe and synthetic
benchmark logs use the `out/bhh-scalar-history-` prefix; the expanded benchmark
uses `out/bhh-scalar-history-short-bench.log` and its summary JSON.
The public 0.3.2 release download predates these development changes.
