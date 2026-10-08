# Big Helmet Heroes coherence and command-header investigation — September 28–29, 2026

This follow-up investigates GPU-to-guest-memory traffic after the
[buffer-budget accounting change](big-helmet-heroes-performance-2026-09-28.md).
The shared Vulkan backend can now reject obsolete, retired storage-image
readbacks before recording a GPU copy. It also retains a valid page-generation
proof after verifying an identical CPU write or a change confined to padding.
Extended validation also exposed a command-header guard that could stop all
later rendering; its registration error is fixed separately from the renderer
optimization.

## False command-header protection

A menu validation run stopped advancing after flip 1216. The command processor
rejected a timestamp release at `0x314f68f160` because it had inferred a protected
allocation header before a submitted range beginning at `0x314f68f164`.
Later releases failed with `GuestMemoryWriteFailed` and queues stopped with
`BackendRejected`. Audio and the host window continued running, so a process
that remains alive is not proof of successful rendering.

Checking only the first packet was insufficient. A later repeat run rejected a
write at `0x304144bad0` before a span beginning at `0x304144bad8`. Reading the
stopped process confirmed a real `SET_SH_REG` packet (`0xc0087600`) immediately
after the eight-byte label. The submission identified an interior command span,
not the start of a separate allocation. Its preceding bytes were valid label
storage, regardless of whether its first packet was complete.

Public submissions and recovered builder tails now register command ranges
without inferring a protected allocator header before them. Prefix validation
uses the same range semantics, so it also permits a legitimate command to write
a preceding label. Compact-address aliases are registered before wait-label
validation. Empty, non-command and truncated-first-packet submissions create no
aliases. Immutable snapshots, contiguous-prefix decoding, unreadable-wait checks
and normal guest-memory access validation remain in place.

Regression tests cover non-command data starting inside a timestamp, valid
command spans at several alignments, a later write into the preceding label,
and a command that itself writes that label. The previous implementation fails
the new cases. Repeat-run results below do not establish that every possible
stall is fixed.

## Change and correctness boundaries

Previously, `flushCachedStorageImage` copied the image to a transfer buffer and
waited for the GPU before discovering that the CPU had already replaced its
texels. The new preflight check applies only to unpinned images whose pages are
already watched. A changed texel invalidates the old image without downloading it;
pending consumers and untracked providers retain the existing path. The host
copy used by preflight also preserves padding for publication. If its page
generation changes while waiting for the GPU, the renderer reads and checks
the guest allocation again before publishing the result.

`storageGuestContentsChanged` previously kept hashing an allocation after its
page generation changed, even when another binding had already rearmed its
shared pages and its texels remained unchanged. It now observes that existing
generation **before** hashing and records it only after proving the texels
unchanged. A write during or after the check invalidates the proof.
Padding changes still preserve the resident GPU result, while changed texels
require a fresh upload. Providers without page tracking retain the hash path.
Neither validation path rearms pages itself: an experimental version did so,
adding page-protection work without a demonstrated menu improvement, and was
rejected. That exploratory trial avoided one 4,450 KiB image readback per sampled
menu frame, but measured a 179 ms median versus the 164 ms control. These earlier
figures are not part of the final comparison after the GPU became available.
Its implementation and executable are not the final build.

The frame log adds `[gpu storage coherence]`: checks, page-generation hits,
bytes examined on the hash path, actual storage-image copies scheduled, and
obsolete readbacks avoided. These counters do not include render-target or
storage-buffer copies. `checked_kib` counts allocation sizes examined, rather
than every additional hash of a copied or detiled scratch buffer.

## Investigation limits

The detailed tutorial trace includes reused addresses with different formats
and extents, including a large color target later described as a small compute
image. Such resources cannot safely share a Vulkan view solely because their
base addresses match. This change does not bypass those conversions or reduce
the game's internal render resolution.

The first diagnostic launch encountered a full E: volume. Six abandoned
temporary pipeline-cache files occupied 8,420,216,110 bytes. They were removed
after the game exited; the live pipeline cache, games and saves were retained.
That launch is excluded from performance comparisons. Detailed graphics traces
also force extra readbacks and image dumps, so their frame times are excluded.
Several automatic-input control attempts remained in the menu rather than
entering the tutorial. Their samples are not used as tutorial baselines. Both
failed header-guard runs, including the incomplete first-packet-only fix, are
excluded from successful performance comparisons.

## Validation and measurements

- 541/541 HLE unit tests pass. Coverage includes false-header registration,
  labels preceding real command spans, explicit header protection and malformed
  command prefixes.
  Reverting the range handling reproduces the false-header error in the new test.
- 187/187 Vulkan unit tests pass.
- The real-device `--storage-cpu-reuse` probe covers plain reads, fingerprints
  and page tracking. It checks CPU replacement, padding-only changes, identical
  writes, repeated resident bindings, a CPU write injected after fingerprinting,
  another injected between preflight and the post-wait generation check, and
  preservation of a row not touched by the shader. A replaced watched image
  must schedule zero readbacks, and an unchanged watched rebind must do zero new
  allocation hashing.
- `--storage-reuse` passes with 320 resident views, 1,152 queued writes and
  eviction under a byte budget. `--layered-volume` passes with 32 layers,
  metadata clears and 3D guest swizzling.

The comparison uses PPSA19943, ReleaseFast, Ryzen 7 7700 and RTX 3070 Ti.
After the maintainer reported that the GPU was available again, both builds
were rerun sequentially. Earlier runs that could overlap the maintainer's GPU
use are excluded from the final performance comparison. Runs use
`PS5_HLE_PROFILE=1`, the same working directory and retained caches. Menu runs
add `PS5_INPUT_MODE=controller`; tutorial runs use automatic input. The control
menu and final tutorial runs last 150 seconds; the final menu check lasts
180 seconds. A separate 100-second launch supplies the screenshot, without
capture work inside either performance comparison.
Builds and GPU probes finish before the comparison starts.
The statistics use the same periodic-sample filter as the previous report:
exclude loading frames over one second and the first 60-flip interval per scene.
These are medians of periodic samples, not a continuous average or a 1% low.

The baseline executable is the previous buffer-accounting build, SHA-256
`29155C35D0352DABA86FF3EF11A0FDD88EAD1307B225AB5D323BEC5AE15FA0A4`.

| Scene / build | Median frame time | Approximate FPS | Periodic samples | Range |
|---|---:|---:|---:|---:|
| Menu, control | 165.5 ms | 6.04 | 8 | 155–184 ms |
| Menu, final | 163 ms | 6.13 | 14 | 156–182 ms |
| Tutorial, final | 280 ms | 3.57 | 5 | 278–313 ms |

The menu difference is about 1.5% with substantially overlapping ranges. This
single pair does not establish a repeatable FPS improvement. Both builds still
move about 122 MiB per sampled menu frame across upload and readback paths.
The final menu logs 26 storage-image checks, 10 page-proof hits, 61 MiB examined
on the hash path, 14 storage-image readbacks and zero preflight discards per
sampled frame. The new early-discard path is validated by the device probe,
but does not demonstrate a reduction in this title's steady menu traffic.

The final menu median includes about 150 ms in submission processing and
13 ms outside it. It still makes about 194 Vulkan submissions per frame,
with 32 ms of fence waits and about 50 ms in compute-image preparation.
These scopes overlap. Buffer-cache churn remains about 240 misses/evictions
per frame at the unchanged 4,096-entry limit.

The final tutorial still uses about 967 draws, 116 dispatches and 260 Vulkan
submissions per sampled frame. Median uploads are about 100 MiB, readbacks
68 MiB, fence waits 36 ms and buffer-cache evictions 1,252. Submission processing
accounts for about 265 ms of the 280 ms frame. Its storage-image preflight
discard counter also remains zero. There is no matched tutorial control from
this comparison because the attempted control remained in the menu; these
five samples do not establish a tutorial FPS improvement. **30 FPS is not reached.**

The world transition includes a 15,666 ms frame: 955 ms in submission processing
and 14,711 ms outside it. The latter needs a separate loading-thread profile;
it cannot all be attributed to GPU work or shader compilation. These loading
frames are excluded from the steady-scene table.

The final runner completed three consecutive timed checks: 180 seconds in the
menu, 150 seconds through tutorial loading and a separate 100-second tutorial
visual run. Their last profiled flips are 1,920, 600 and 360 respectively, with
no logged header-guard failures, stopped queues, guest faults or device loss.
The harness ended each process at its time limit; long-session stability,
general save recovery and a full playthrough remain unverified.

[The current tutorial screenshot](../images/big-helmet-heroes-coherence-tutorial.png)
is an unedited 1765×993 capture of the actual game window from the final runner,
taken 75 seconds into the separate visual run. The character, HUD, windmills
and Move/Sprint prompts are visible. Rendering artifacts remain. Presentation
output is 1920×1080; traced internal resources still include 3840×2160 depth
and 2848×1600 intermediates.

Local logs, executable hashes and launch environments are retained in
`out/bhh-span-menu-control`, `out/bhh-span-menu-final`,
`out/bhh-span-tutorial-final` and `out/bhh-span-tutorial-visual`.
`out/bhh-free-tutorial-control` records the attempted control that remained in
the menu. Failed intermediate builds are recorded separately in
`out/bhh-residency-menu-final` and `out/bhh-free-tutorial-final`.

## Remaining cost

The storage-image change does not remove the large render-target and buffer
round trips. Identical guest addresses are insufficient evidence of identical
images: the observed format and extent changes need an explicit conversion or
proof that the old contents are dead. The next substantial reduction needs to
keep those producer/consumer transitions on the GPU while preserving guest
layout and CPU visibility, then batch submissions across dependencies that do
not require a host wait. Simply suppressing repeated packets, evictions or
release writes would lose required work.

Steady frame cost and first-use pipeline stalls remain separate problems.
Profiler scopes overlap; resource preparation, draw/dispatch time and fence
waits cannot be added as independent portions of a frame. `resident_kib` counts
resource reuse during the frame and is not physical VRAM occupancy.

## Local executable

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast on September 29, 2026
at 01:03:22 (Europe/Minsk), 38,433,280 bytes. SHA-256:

```text
C7108D992475F21C328EDCA6D854A69885096866B1B09F61D5834141B8D2D1FB
```

The public 0.3.2 download predates these development changes.
