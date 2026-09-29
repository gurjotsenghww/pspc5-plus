# Big Helmet Heroes: cheaper buffer eviction — September 29, 2026

This follows the [shared texture-copy optimization](big-helmet-heroes-wide-tiles-2026-09-29.md).
The renderer now maintains buffer-cache recency directly. Previously every
capacity eviction scanned all 4,096 retained entries to find the oldest eligible
buffer. The new search starts at the oldest entry and stops at the first
eligible candidate. Hits, insertion and removal update the order in constant
time, without allocations. A fully pinned cache can still require a full walk.

This is a shared renderer change, with no title or shader signature condition.
The default entry limit, memory budget, descriptor pinning, GPU write publication,
queued-reader lifetime and content-validity checks are unchanged. Byte-budget
trimming repairs the order after a dense-array swap removal without changing
the moved entry's age. Legacy descriptor-slot reuse keeps its existing policy.
The new `victim_steps` profile counter records entries examined during selection.

## Matched game measurements

The control contains the preceding texture-copy implementation and the same
new diagnostic input mode, but retains linear victim selection. Its SHA-256 is
`0DE2E1FEFEB0F92646AAB5DF834D6AC84CA889A8D7A0423A527B7D306170570B`.
Both builds run PPSA19943 on the Ryzen 7 7700 and RTX 3070 Ti, in ReleaseFast,
with `PS5_HLE_PROFILE=1`, one copy participant and 4,096 buffer entries.
Menu launches last 150 seconds with controller input. Tutorial launches last
180 seconds with `PS5_INPUT_MODE=scripted`: existing bring-up button pulses
continue, while physical keyboard and controller events are ignored. The
launcher and normal interactive input are unaffected. This avoids the scene
changes that invalidated the preceding report's daytime tutorial comparison.

Compilers, other device probes and screenshot capture do not overlap these
performance runs. All launches use the same working directory and retained
caches. Statistics exclude loading frames over one second and the first
60-flip interval in each scene. They describe periodic frame samples, not
continuous averages or 1% lows.

| Scene / build | Median frame | Approximate FPS | Samples | Range |
|---|---:|---:|---:|---:|
| Menu, control | 164 ms | 6.10 | 11 | 158–228 ms |
| Menu, new | 161 ms | 6.21 | 11 | 152–176 ms |
| Tutorial, control | 287 ms | 3.48 | 7 | 263–299 ms |
| Tutorial, new | 277 ms | 3.61 | 8 | 259–301 ms |

The sampled ranges overlap. These limited comparisons do not establish a
repeatable whole-game FPS gain. The change removes a known linear search; it
does not remove cache misses, GPU dependencies or resource transfers.

The new menu median has 250 evictions and 250 victim-selection steps;
the tutorial medians are 1268 and 1268. At the unchanged full capacity,
the old selection loop would examine 4,096 entries for each such capacity
eviction. This count reduction is not a corresponding FPS multiplier.

In the new tutorial samples, submission processing still takes 262 ms of
a 277 ms frame, with about 34.6 ms of fence waits, 272 Vulkan
submissions, 105.4 MiB uploaded and 63.9 MiB read back. Timing scopes
overlap. Resource preparation, transfers, synchronization and loading stalls
remain the next substantial costs. 30 FPS has not been reached.

The compute-buffer preparation scope falls from a median 11 to 10 ms in the
menu and from 35 to 31 ms in the tutorial. Compute-image preparation remains
48 ms in the menu and 44 ms in the tutorial. These overlapping profile scopes
help locate remaining work; they are not independent frame-time savings.

## Rejected capacity experiment

Before changing victim selection, two 150-second menu launches tested 4,096
and 8,192 entries with the same experimental executable and one copy participant.
At 4,096 entries the median was 162 ms (6.17 FPS, 11 samples, 150–175 ms);
at 8,192 it was 173 ms (5.78 FPS, 10 samples, 168–179 ms). Median misses/evictions
fell only from 241 to 223. This did not justify a larger cache, and the entry
limit remains 4,096. Those runs are separate from the final implementation's
matched comparison. Local logs are under `out/bhh-cache-menu-4096` and
`out/bhh-cache-menu-8192`.

## Validation and capture

All 190 Vulkan unit tests pass, including the three new recency/eligibility
tests. The standalone recency model also passes in ReleaseSafe. All 541 HLE
unit tests pass with the scripted-input change. Real-device probes pass:

- `--expanded-buffer-cache`: full capacity, hot-entry retention and CPU updates.
- `--buffer-cache-budget`: actual backing accounting and budget eviction.
- `--clean-buffer-retention`: retained ranges and queued readers.
- `--buffer-reuse`: legacy reuse with and without waits.
- `--buffer-rename`: pool limits, oversized allocations and pending readers.
- `--buffer-view-coherence`: overlapping views and GPU-authored bytes.

The recency tests compare 10,000 deterministic operations against an independent
ordered-list model and cover every removal/moved-slot adjacency combination in
a small cache. Renderer tests exercise dirty candidates, active bindings,
replacement of a descriptor's own buffer, changed recency and a fully pinned
cache. The expanded device probe now fills all 4,096 entries, verifies CPU
replacement and rebinding including the highest slot, and checks that pressure
preserves a recently used buffer while examining just one eviction candidate.

[The new tutorial screenshot](../images/big-helmet-heroes-buffer-recency-tutorial.png)
is an unedited 1765×993 capture of the actual game window, taken about
55 seconds after launch following profiled flip 240. It shows the
character, HUD, windmills and Move/Sprint prompts. The separate visual run is
excluded from the performance table. Output is 1920×1080, while internal
targets can be larger. Rendering artifacts remain; full playability and
long-session stability are unverified.
All four matched launches and the separate 150-second capture run advance
frames without logged command-header guard failures, stopped queues, guest
faults, device loss or panics. The capture run reaches profiled flip 540.
Processes are ended by the harness at their time limits. This is a limited
startup/scene check, not a full playthrough.

The website passes all 56 tests, TypeScript checking and a production build.

Local manifests, executable hashes and raw logs are retained under
`out/bhh-lru-menu-control2`, `out/bhh-lru-tutorial-control2`,
`out/bhh-lru-menu-final`, `out/bhh-lru-tutorial-final` and
`out/bhh-lru-visual-final`. The earlier interrupted `bhh-lru-menu-control`
case is excluded. Probe and build logs use the `out/bhh-lru-` prefix.

## Local executable

`zig-out/bin/game-run.exe` was rebuilt in ReleaseFast at 2026-09-29 12:53:29
(Europe/Minsk), 38,669,824 bytes. SHA-256:

```text
C6278D1F66FE778650EE2C5401485A1D20FC5583025C2FCBBB41D61712C77DBE
```

The public 0.3.2 release download predates these development changes.
