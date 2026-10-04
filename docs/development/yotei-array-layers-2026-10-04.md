# Yotei array-layer coherence investigation

The October 4 investigation continues toward the scene after the tree and the
following cinematic. Controllable gameplay has not yet been confirmed.

## Control run

The October 3 candidate (`8b375c2139e23e47b27a667bba0271541d851368bb073b779864494a9c441e12`)
was launched with the default renderer cache budgets, 1920×1080 output, Speed,
and the Performance game preference. Original-culling diagnostic switches were
not enabled. A 30.046-second interval during the tree transition presented 31
frames: **1.032 FPS**. This is an animated setup transition, not gameplay FPS.
Vertical artifacts and missing/dark scene detail remain visible.

The run passes brightness, difficulty and experience selection. During the next
loading transition, Windows commit reaches 59,753,652,224 bytes against a
60,385,345,536-byte limit. The test harness deliberately terminates its process
after three samples below 768 MiB of commit headroom, at 1,179.629 seconds.
This is not a spontaneous guest crash. The last compiler inspection shows one
active foreground job; the 1,026-entry compute warmup had finished without a
reported failure.

A warmed frame (flip 1443) takes 1,019 ms, uploads 701,610 KiB and reads back
412,276 KiB. Graphics resource preparation accounts for 389 ms and fence waits
for 219,699 µs; these categories overlap and must not be added together.
Neither graphics nor compute pipeline creation misses occur in that frame.

Five sampled RG8 arrays, 2048×2048 with nine or ten layers, account for 376 MiB
of repeated full uploads. Matching render targets exist for individual slices,
but cannot serve the complete array view directly.

## Renderer changes under test

Unmipped color-array backing observations and publication previously included
every preceding slice. Changing a neighboring slice could therefore invalidate
a resident GPU producer whose own bytes had not changed. Restrict both the
observation and publication to the selected slices, as already done for mip
subresources. This also reduces fingerprint and guest-write spans.

A previously uploaded sampled array can now receive compatible dirty render
target slices by ordered GPU copies. Preserve the other layers from that
initialized snapshot. Require unchanged tracked CPU backing, matching source
layout and format, and no unhandled dirty producer. Reject same-batch prepared
bindings, ambiguous overlapping producers, metadata/compressed surfaces and
canonical-alias mode. Fall back to normal publication and upload when these
conditions cannot be proved. Report successful copies in `gpu sampled arrays`.

## Validation

- Eleven ReleaseSafe color-surface tests pass, including a regression for
  neighboring unmipped slices with linear, 4 KiB and render-target tiling.
- `vulkan-smoke --sampled-array-refresh` passes with timeline scheduling both
  disabled and enabled under Khronos validation, without validation errors.
  It checks two queued color revisions, nonzero untouched layers, CPU-write
  rejection, prepared-binding protection, and zero extra texture upload/readback.
- `build-vulkan-smoke` builds probes without running them. Run these probes from
  a separate working directory so their driver cache cannot replace the game's
  `vulkan_pipeline_cache.bin`.

## Candidate run

The ReleaseFast candidate is SHA-256
`3b1e2b38b86d47fdedf6e95fc1273e509f126faa3e241570b99e1b8f62bd3ef4`.
It starts with the same default renderer cache budgets and game/output presets as
the control. No cache budgets or original-culling switches have been changed
through the tree measurement.

| Visible interval | Presented frames | Duration | FPS |
| --- | ---: | ---: | ---: |
| Wolf brightness calibration | 37 | 30.046 s | 1.231 |
| Tree transition into difficulty selection | 37 | 30.046 s | 1.231 |

The tree interval improves over the control run's 1.032 FPS in this pair of
launches. Cache history and animation phases are not identical, so this is not
a universal speedup estimate. No profiler, build, input or screenshot capture
runs during either measurement.

The tree's bark and branches are visible in the candidate, whereas the control
capture at difficulty selection is largely dark. Bright vertical streaks remain.
In-game counters confirm array refreshes: for example, flips 846 and 847 each
copy eight layers into two sampled arrays. Other arrays still use full uploads.

![Candidate tree at difficulty selection; bark is visible but vertical streaks remain](../images/yotei-array-layers-tree-2026-10-04.png)

After experience selection the next loading transition again approaches the
Windows commit limit. Reducing the live storage-image budget from 2,560 to
1,536 MiB does not prevent the diagnostic guard from stopping the process:
58,814,091,264 bytes committed against a 59,294,818,304-byte limit. This budget
change happens after the reported measurements. The last inventory records
22,050,426,880 private process bytes; the next scene and character control are
not confirmed. This is another deliberate diagnostic stop, not a guest crash.

## Shared storage transfer buffer

The tree inventory contains 1,429,907,328 bytes of persistent host transfer
buffers for storage images, in addition to the GPU images themselves. Ordinary
batched uploads already use the upload ring. Replace those per-image host
mirrors with one lazily allocated buffer that grows to the largest transfer.
Keep the image cache budgets and contents intact.

Readbacks and depth/stencil bridges order their reuse with transfer barriers.
Growing the buffer defers destruction of the previous allocation until its
queued users retire. Uploads outside the ring wait before overwriting shared
host memory, including the initial upload to a newly created image. Readbacks
still wait for their GPU result before publishing guest bytes.

ReleaseSafe native probes pass with Khronos synchronization validation:
`--storage-reuse`, `--storage-cpu-reuse`, `--depth-storage`,
`--color-cube-publication`, and `--sampled-array-refresh`. No validation errors
are reported; the layer emits a configuration deprecation warning for the
environment variable used to enable synchronization validation. The storage
probe verifies 320 resident views without allocating a transfer buffer, 1,152
queued writes, a four-byte shared readback buffer, dirty-image eviction,
buffer growth/reuse while copies are queued, and a later CPU upload. These are
correctness and allocation checks, not game FPS measurements.

The combined ReleaseFast runner is SHA-256
`9bb91d692ceacf578afc7168ad9085e103492a07743bebfa3445e4dce5b8f5cc`.
At this checkpoint, `zig-out/bin/game-run.exe` and its PDB were updated to this
build; the previous installed pair was retained locally for rollback. Public
release archives are unchanged.
With unchanged default cache budgets, its tree transition presents **38 frames
in 30.047 seconds: 1.265 FPS**. The earlier array-only candidate presents 37:
one extra frame does not establish a meaningful FPS gain. Both show bark and
branches, with bright vertical streaks still present.

The new tree inventory retains a **72 MiB** shared storage transfer buffer,
versus approximately **1,364 MiB** of per-image buffers in the array-only tree
inventory. Private process memory is 14,337,359,872 bytes versus
15,554,560,000 bytes in those snapshots. Cache contents and animation phases
differ slightly; the structural removal of per-image buffers is verified, but
the total process-memory difference is not a controlled benchmark.

![Combined candidate at difficulty selection](../images/yotei-shared-transfer-tree-2026-10-04.png)

## Continuation into the cinematic

The combined build passes the bonus notices, wolf brightness calibration,
Medium difficulty and Standard experience selection. The camera moves past
the tree into a very dark cinematic. Opening Options displays `PAUSED` and a
subtitle toggle, confirming that this is still the cinematic rather than
controllable gameplay. Resuming removes that overlay, but character control
has not been established. The owned diagnostic process is deliberately stopped
after approximately 36 minutes for the next isolated build and native tests.

Flip 1384, before any live cache-budget changes, takes **59,275 ms**. Graphics
pipeline creation accounts for **35,376 ms across 550 misses**; the frame also
uploads 6,412,920 KiB and reads back 2,197,188 KiB. Frame categories overlap and
must not be added together. This is a cold-transition stall, not a stationary
gameplay FPS sample. A later pipeline inventory contains 1,379 graphics
pipelines and 1,180 distinct exact shader pairs; trivial render-state
deduplication alone cannot remove most of that compilation.

Host commit approaches the limit again. To continue diagnosis, the live sampled
budget is changed from 2,048 to 1,024 MiB and the storage budget from 2,560 to
1,280 MiB. The sampled budget is subsequently raised to 1,536 and then set to
1,280 MiB; the render-target limit is reduced from 128 to 64. These changes are
**diagnostic only**, occur after the reported tree measurements, and are not
installed defaults. They reduce retained resources but cause substantial churn:
later frames upload roughly 3.3–3.8 GiB of sampled textures. Even with only
one or two new graphics pipelines, individual frames still take 8–15 seconds.
Some of those frames render the pause overlay, so they are not reported as
gameplay FPS or a controlled comparison against the default budgets.

One pixel-shader resource lookup is unresolved (`s28`, program
`0x800026ed00`, instruction `0x8b4`), and its draw is rejected. Zero unsupported
compute-program reports do not establish complete shader or resource coverage.
Dark rendering, tree streaks, resource churn and character control remain open.

![Very dark post-tree cinematic after resuming from pause; character control is unconfirmed](../images/yotei-post-tree-dark-2026-10-04.png)

## Read-only storage-image reuse

The sampled fallback cache includes the storage producer's eviction sequence
in its content identity. A read-only storage binding advances that sequence
without changing any texels, needlessly invalidating an already uploaded
sampled view. Use the existing storage content generation instead. Actual
uploads, image writes, clears and depth-to-storage copies advance this
generation; read-only bindings do not.

The extended `--sampled-storage-refresh` native probe reproduces the problem
before the change: a read-only image dispatch causes a third sampled upload
where only two are expected. With the change, four cases pass under Khronos
synchronization validation: image/buffer producers, each with timeline
scheduling disabled/enabled. Pixel readbacks verify pending and published GPU
writes, a sampler change, read-only reuse, and a later direct CPU update outside
the sampled texture's sparse probe. No validation errors are reported.

The ReleaseFast runner is SHA-256
`7d91b76040d7c9136de8f5b59738626d48bf22ee01aa0e0c788455e7b58364da`.
The installed executable and PDB are updated; the preceding pair remains in a
local backup. The game repeat starts with the unchanged default cache budgets,
1080p output, Speed preset and Performance game preference.

| Visible interval | Presented frames | Duration | FPS |
| --- | ---: | ---: | ---: |
| Wolf brightness calibration | 38 | 30.044 s | 1.265 |
| Tree transition into difficulty selection | 38 | 30.044 s | 1.265 |

The tree result matches the preceding shared-transfer build. **No game FPS
gain is demonstrated for this additional change.** Bark and branches remain
visible, and the bright vertical streaks remain. Neither measurement overlaps
input, profiling, screenshot capture or a background build. The new tree
inventory retains the 72 MiB shared transfer buffer and records 14,654,386,176
private process bytes; this is not a controlled memory comparison.

A separate eight-second resource trace is enabled and then restored before
these measurements. It records unresolved buffer-descriptor discovery in
compute and export-stage branches; no `storage incomplete` fallback is reported
in that short interval. The per-frame `storage_unresolved` counter reaches
approximately 900, but includes potentially inactive branches and is not proof
of that many executed missing accesses. First-occurrence graphics resource
failures now retain bounded scalar diagnostics without requiring verbose
buffer-lifetime tracing.

## Illustrated movie and compilation stalls

The read-only reuse build continues past the tree and the dark 3D cinematic
into a clearly visible illustrated narrative movie. This is progress beyond
setup, **not confirmation of character control**. No pause input is used in
this repeat.

![Illustrated narrative movie after the tree and dark cinematic](../images/yotei-post-tree-movie-2026-10-04.png)

A 30.045-second interval during the cold 3D transition presents one frame
(0.033 FPS). It includes first-use compilation stalls and is not a warmed
gameplay measurement. With the default 2,048 MiB sampled-image budget, later
flip 1491 takes 10,429 ms despite only one graphics and three compute pipeline
misses, totaling 8 ms of pipeline creation. It uploads 1,775,144 KiB of textures
and records 5,079 sampled misses and 5,016 evictions. Graphics resource
preparation takes 6,620 ms, with 5,060,485 microseconds of fence waits across
the frame. These overlapping categories must not be added together.

At 13:37:42 local time, the sampled-image budget is increased live from 2,048
to 2,560 MiB; storage-image and render-target budgets remain unchanged. The
scene switches to video immediately afterward. Lower texture churn in the
movie therefore **does not demonstrate a benefit from this budget change**.
The installed default remains 2,048 MiB. The live experiment is reverted to
that value at 13:49:46 to preserve memory headroom during compilation.

Subsequent loading stalls hold the last movie image on screen. Flip 1605 takes
239,431 ms, with 234,886 ms spent creating 15 compute pipelines. Flip 1606
takes 105,038 ms, including 104,146 ms of compute pipeline creation. A short
thread sample finds active NVIDIA compiler work while the submitted GPU tick
is already complete. The foreground compiler queue remains active; its startup
warmup has finished. These are observed compilation stalls, not proof of a
deadlock or a game crash.

Two pending compute modules are captured locally, approximately 1.6 MiB each.
One has a 364-case dispatcher; the other has 151 cases and 140 loops. The first
passes SPIR-V validation. An offline `spirv-opt -O` experiment reduces it from
1,628,004 to 1,448,996 bytes in 3.50 seconds, also passing validation. This has
not yet been timed in the driver or executed for comparison, and is not
enabled in the renderer. No game shader bytes are published.

The resource diagnostic still records a rejected pixel-shader draw at
`0x800026ed00`, instruction `0x8b4`, sampled resource `s28`. Its descriptor
comes through a vector-loaded pointer and nested material table; a correct
fix must resolve and stage that table, not substitute a dummy texture.
Post-movie control, steady gameplay FPS, dark lighting and remaining tree
streaks are still open at this checkpoint.
