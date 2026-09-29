# Yotei shader resource audit and repeated-query cost

The renderer has real resource gaps even when shader instructions decode
successfully. This investigation fixes missing resource preparation for
floating-point buffer atomics and removes repeated static register-definition
walks. It does not establish complete shader support, a stable startup, or
30 FPS.

## Corrections

`buffer_atomic_fmin` and `buffer_atomic_fmax` were decoded and translated, but
the shared resource checkpoint and writable-buffer preparation lists omitted
them. Effect classification also omitted these operations. A kernel containing
only one of these atomics could therefore be classified as having no external
effect; otherwise its destination might never be staged or published as a
writable buffer. All four lists now include both instructions.

The correction applies to every title. A native Vulkan probe loads the buffer
descriptor from guest memory with `s_load_dwordx4`, dispatches each atomic
through normal resource preparation, publishes its write, and verifies the
result and an untouched adjacent word. Both decoded and typed-IR translation
paths pass, for four cases in total.

Seven resource-candidate queries now use the analysis owner's existing bounded
cache of reaching definitions. Three repeated instruction-PC searches also
use its cached positions. The cache retains only immutable instruction/CFG
facts, including ambiguous results. It verifies allocation identity, has a
4,096-entry limit, and falls back on allocation failure. Guest values, buffer
contents and runtime descriptors are still read afresh.

## Shader coverage and diagnostics

A read-only snapshot from the updated native run contained 624 cached programs
and 501,588 decoded instructions across 371 opcode kinds. Each retained code
blob was compared with the current guest bytes before inclusion. No
`unknown` or `unsupported` opcode occurred in this snapshot. 109 programs
contained floating buffer atomics: 325 min and 325 max instructions.

This is an observation of that cache snapshot, not an exhaustive audit of the
game. A successful decode does not prove a successful resource binding or
faithful execution. The run still reports `UnsupportedSampledImage` and
`GuestMemoryReadFailed` draw/dispatch failures. Existing translation fallbacks
for an unbound buffer may return zero/default load values or omit stores.
Existing title-specific visibility/GDS emulation also remains in use.

The new `[gpu gaps]` profile line records draw failures, dispatch failures,
unsupported compute programs, and unresolved/null/rejected storage resources.
For example, flip 779 reported 24 failed draws and four failed dispatches;
flip 780 reported neither, but still had 2,714 unresolved storage preparations.
Storage-preparation counts are not counts of executed missing GPU accesses:
some instructions can belong to an inactive branch. Detailed storage warnings
are bounded and deduplicated by program, PC and reason, while per-frame totals
continue to count occurrences.

## Performance evidence

An offline ReleaseFast microbenchmark used the twelve largest programs from
the validated snapshot. It checked every selected resource-register query
against the uncached result, then repeated those queries ten times. All
237,920 timed results matched: uncached queries took 1,627,123 microseconds,
and warmed cached queries took 2,419 microseconds. This deliberately isolates
repeated static queries; it excludes decoding, cache construction, guest memory
access, uploads, GPU work and presentation. It is not an FPS speedup claim.

The updated native run still had substantial transfer and preparation costs.
At flip 780 it reported 875 ms total, 467 ms in 1,388 dispatches, 158 ms in
graphics resource preparation and 156 ms in fence waits across 210
submissions. Uploads were about 223 MiB and readbacks about 170 MiB. These
categories overlap and must not be added as independent frame costs.

Both the preceding executable and the updated executable crashed during
startup in the control launches, so no matched steady-state FPS comparison
was obtained. The updated run reproduced the guest read fault at `0x133214d`
with target `0x50d3400800`; the preceding run faulted during a guest `memcpy`
store reached from `0x1177bba`. The producer-count problem remains unresolved.

A subsequent diagnostic repeat caught the oversized producer for the first
time. A hardware watchpoint observed the reset of `0x6af91c8` to zero, followed
by `lock xadd` at `0x1177c8b` adding `0x3f23fa79` (1,059,322,489).
The value came from `[object + 0x120] + 0x20`: object `0x1000c6fb60`, header
`0x50c12ffd30`. Nearby header words also resemble floating-point graphics
data. The call clamps its copy to 4,096 records but leaves the total oversized;
the later converter faults. This identifies the invalid producer input, not
the writer that corrupted it. No count clamp or guest-memory patch was added.
The debugger detached after the process exited with code 1. Its timing is
unsuitable for FPS comparison.

Another diagnostic repeat also exited with code 1, this time at
`libc.prx+0x3d55`, reached from `0x1177bba`, while writing to
`0xffffffd3becba100`. It faulted before an oversized write to the watched
`0x6af91c8` counter, so the attempted GPU-buffer overlap snapshot was not
triggered. The earlier counter/copy path also needs to be observed. This is
not evidence that a GPU readback caused either fault.

## Tree artifact

The [earlier real-window tree capture](../images/yotei-warmup-priority-tree.png)
shows the reported thin vertical orange streaks across the trunk. Their first
producing pass has not been isolated. The four launches in this investigation
(one preceding executable, three updated executable) exited before the
requested draw-by-draw capture at flip 1,000. No new tree screenshot or
before/after artifact comparison was obtained. The existing image remains an
artifact reference, not evidence that the new atomic fix repairs the tree.

No material, particle pass, or guest shader was disabled to hide the streaks.
Startup/header corruption must be made reproducible under observation before
the frame trace can reliably distinguish geometry/material errors from a
later compositing effect.

## Local renderer comparisons

The local KytyPS5 source separates an immutable resource plan, refreshed
runtime snapshots and module-affecting specialization in
`ResourceMaterialization.h/.cpp`. This supports caching structural work while
keeping guest addresses and descriptor payloads current. Its buffer-address
emitter is also a useful reference for stride and swizzle handling.

sharpemu's `BufferCandidateTablePlanner.cs` proves that descriptor words come
from the same SRT and bounds a dynamic candidate set from an unsigned induction
loop. `EmbeddedVertexFetchDetector.cs` removes only proven fetch-prolog work
when replacing it with fixed-function attributes. These are useful next steps
for unresolved resources and vertex preparation; this change does not claim
to implement those complete passes. No source was copied from either project,
and no comparative FPS measurement of those emulators was performed.

## Validation and build

- GPU-module ReleaseSafe tests: 240/240 passed.
- Native Vulkan loaded-descriptor atomic probe: all four cases passed.
- ReleaseFast `build-game-run`: succeeded.
- Static-query microbenchmark: identical results.
- Website lint and typecheck: passed; website tests: 56/56 passed.

Installed development executable: `zig-out/bin/game-run.exe`, SHA-256
`8811654994c55d712d889b4314fba51a10ed9610f5ed1aebab5a0411db2ffa99`.
The matching PDB is installed alongside it. The public release archive is
unchanged.

Local evidence is retained under `out/yotei-render-audit-20260929/`,
`out/yotei-render-baseline-20260929/`,
`out/yotei-render-patched-20260929/` and
`out/yotei-render-trace-20260929/` and
`out/yotei-render-trace-repeat-20260929/`. Game shader bytes remain local and are not
published. The baseline's initial cache snapshot is explicitly marked invalid
because its record stride was incorrect; none of its shader statistics are
used here. The updated snapshot uses the matching PDB's native structure size
and verifies captured words against guest code.
