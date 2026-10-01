# Subnautica: Below Zero — new-game startup investigation

Test title: PPSA02457 v1.022.125, supplied locally. These are development-build
results; the published 0.3.2 archives are unchanged. Installed game content and
existing saves were not edited.

## The mode-selection blocker

The original runner accepted the Survival selection but left the New Game
panel open. A debugger confirmed an `IndexOutOfRangeException` in
`Path.InsecureGetFullPath`, called through `SaveLoadManager.ClearTemporarySave`
and the `CreateSlotAsync` coroutine. The main-menu coroutine retained its busy
flag, so further button presses did not restart the operation.

Unity's temporary cache path was empty. The AppContent service returned
`/temp0`, but the filesystem did not attach that mount. The runner now prepares
`out/temp0/<title-id>` and mounts it as writable scratch storage before guest
execution. It uses the same sanitized title identifier as other per-title data
and keeps installed content read-only. The title creates its `TempSave`
directory and proceeds to the world-loading screen.

## Guest stack roots during garbage collection

A run with only the filesystem fix hit a contained worker fault in
`Throttle.Execute`, at `Il2CppUserAssemblies.prx + 0xd0a95f`. The object still
held by the worker had become a free-list entry. The next collection then
waited for the terminated worker on `SuspendSemaphore`.

The emulator delivered Unity's suspension callback from a separate firmware
stack and put the address of a local context buffer in the guest RSP field.
Consequently, the collector could miss the interrupted guest stack. The title's
PS5Util callback reads RSP at context offset `0xf8`; the local KytyPS5 source
also documents that PS5 context layout.

The firmware stack bridge now spills all six SysV nonvolatile general-purpose
registers onto the interrupted stack before switching. Signal delivery exposes
that stack pointer and the saved registers in the PS5 context. Nested firmware
calls retain the original snapshot. This is shared runtime behavior, with no
game-address patch and no forced semaphore completion.

A subsequent default-worker run with this fix lasted until the deliberate
20-minute diagnostic deadline without a contained guest fault. Main-scene
objects appeared and the graphics workload expanded, but presentation became
black; this observation alone did not establish playable gameplay.

## Deferred images after guest memory is released

Bounded live diagnostics found hundreds of `GuestMemoryReadFailed` draw
failures. A breakpoint isolated one repeating failure in
`commitGuestColorTarget`: it tried to read an old 1920×1080 target at
`0x255790000`, spanning `0x870000` bytes. A native memory query found a reserved,
uncommitted hole at `0x255ec4000` of length `0x3c000` inside that old range.
The completed-frame cache kept retrying the pending writeback, preventing its
oldest entry from being reused.

Render targets now remember whether their backing was fully accessible when
created and pass that evidence to completed frames during later readback.
Recording residency only at readback was too late: the observed stale target
was already partially unmapped by then. If writeback fails and the embedding confirms that this formerly
accessible range is now incomplete, the obsolete record is invalidated. A read
failure in a still-accessible allocation, an initially inaccessible range, or
an embedding without a residency callback retains the error. The change does
not synthesize missing pixels or silently accept arbitrary failed reads.

## Final live check and remaining blocker

The final installed build (`1d90211e…`) was launched with the default compiler
and resource workers, keyboard input, speed mode and 1080p output. The
interaction sequence reached Survival and produced the loading capture below.
It subsequently repeated the `Throttle.Execute` null read at
`Il2CppUserAssemblies.prx + 0xd0a95f`, followed by further guest faults. Thus the
stack-context correction fixes a demonstrable runtime defect but **does not
fully resolve the worker/GC failure**. The earlier 20-minute fault-free run was
not sufficient evidence of stability.

![World-loading screen in the final development build](../images/subnautica-below-zero-new-game-loading.png)

The render-target residency snapshot was moved from late readback to attachment
creation after the first cache-guard experiment proved too late to recognize
the old allocation. The final live check faulted before establishing that the
black-screen/draw-failure sequence is resolved. That graphics fix has focused
test coverage; a successful loaded-scene validation remains outstanding.

New Game's initial mode-panel blocker is resolved. Playable gameplay, save
persistence, audio correctness and stable world loading remain unverified.
No FPS improvement or 30 FPS result is claimed.

## Validation

- ReleaseFast runner build passed.
- 47 focused tests passed: filesystem and temporary mount behavior, firmware
  stack switching, native bridge behavior, signal contexts, and deferred frames.
- The register-root fixture places a sentinel exclusively in R12 across the
  assembly stack switch and checks both its visibility and preservation.
- The context fixture verifies that the collector's scan starts below a live
  caller-stack root even across nested firmware calls.
- The frame fixture covers partial unmapping, unknown prior residency, missing
  residency callbacks, and read failure while memory remains accessible.

The installed runner and matching PDB from the final build have SHA-256 hashes:

```text
game-run.exe  1d90211e7d1d5fe94945ec7c153e21bcadc4400947a81100896ef72276d06884
game-run.pdb  41f98dcfb8f1a2781f4cc2361757d7955f430cef2ac4b9071835dfe08a05bfd1
```

Local evidence is retained under `out/subnautica-new-game-*`,
`out/subnautica-temp0-*`, and `out/subnautica-gc-*`. Full logs and extracted game
metadata are not distributed with this report. Captures are unedited client
images of the actual game window, 1765×993 pixels on this desktop with 1080p
guest output; they are not described as native-resolution screenshots.
