# Kernel MemoryPool support — 8 October 2026

Six previously missing `libkernel` exports now have implementations in
`src/hle/libs/kernel_memory.zig`, backed by the shared physical-memory section
and mapping table in `src/memory/root.zig`.

| Export | NID | Behavior |
|---|---|---|
| `sceKernelMemoryPoolReserve` | `pU-QydtGcGY` | Reserve a virtual arena in 2 MiB units, with fixed/hinted placement and alignment checks |
| `sceKernelMemoryPoolExpand` | `qCSfqDILlns` | Donate aligned 64 KiB physical blocks from the direct-memory budget |
| `sceKernelMemoryPoolCommit` | `Vzl66WmfLvk` | Map donated backing into a reserved arena, including noncontiguous physical spans |
| `sceKernelMemoryPoolDecommit` | `LXo1tpFqJGs` | Return physical blocks while retaining the virtual reservation |
| `sceKernelMemoryPoolBatch` | `YN878uKRBbE` | Apply commit, decommit, protect, and type/protect entries in order; report the completed prefix on failure |
| `sceKernelMemoryPoolGetBlockStats` | `bvD+95Q6asU` | Report available and allocated 64 KiB blocks, with bounded output writes |

The ABI and observable baseline behavior were checked against the local
KytyPS5 checkout at `79a91ecfafea899e25dc0df0df6ffb55a8f3cc58`, specifically
`src/kernel/memory.h`, `src/kernel/memory.cpp`, `src/libs/libKernel.cpp`, and
`tests/VirtualMemoryAllocationTests.cpp`. The implementation uses PS5PCEM's
existing allocator, host mappings, synchronization, and page tracking.

## Ownership and error handling

Physical donations remain part of the direct-memory budget. Ordinary direct
maps, including the legacy BatchMap fallback for untracked ranges, cannot map
them. Fixed direct/flexible maps and ordinary virtual reservations cannot
overwrite pool arenas. A physical release refuses blocks still committed to
an arena; releasing unused donations removes them from pool statistics.

Decommit preflights the entire requested range before removing any mapping.
Reserved portions are harmless no-ops. Committed blocks return to the free
pool, preserving shared physical contents for reuse. `sceKernelMunmap` returns
blocks too, but removes the virtual reservation. Pool unmaps require complete
64 KiB blocks. Names and ownership survive protection splits, recommits, and
virtual queries. Pooled pages do not consume the flexible-memory budget.

Host commit failure rolls back the completed mapping prefix. Mapping-table
capacity is reserved before host changes, including enough space for rollback.
Adjacent compatible reservations coalesce after decommit; physical release
compacts block bookkeeping in one pass.

## Validation

The complete HLE suite passes **574/574** tests and the memory module passes
**32/32** tests on Windows x86-64, using `ReleaseSafe`.
The `ReleaseFast` runner build completes all **9/9** steps. The installed
`zig-out/bin/game-run.exe` was updated and signed with the existing PS5PCEM
certificate and a DigiCert timestamp. Its startup smoke check reaches the
expected `FileNotFound` result for a deliberately absent guest executable.

Windows x86-64 tests exercise physical data retention across decommit/recommit,
fragmented donations separated by an ordinary allocation, exhaustion without
partial commits, virtual-query flags and names, unchanged flexible usage,
ordinary unmap/release accounting, rejection of overlapping direct mappings,
batch prefix counts, CPU/GPU protection metadata, memory-type changes, invalid
ranges and output pointers, truncated statistics, host-map failure rollback,
and allocation-failure preservation of live mappings.

Commands:

```powershell
zig build test-hle -Doptimize=ReleaseSafe -j2 --cache-dir out/zig-local-cache --global-cache-dir out/zig-global-cache --summary all
zig test src/memory/root.zig -O ReleaseSafe -lc --cache-dir out/zig-local-cache --global-cache-dir out/zig-global-cache
zig build build-game-run -Doptimize=ReleaseFast -j2 --prefix out/memory-pool-20261008 --cache-dir out/zig-local-cache --global-cache-dir out/zig-global-cache --summary all
```

## Limits

This closes the six missing export registrations, not every possible pool
operation. Batch operation 5 (`MOVE`) returns `EINVAL`, as in the reviewed Kyty
implementation; its complete contract is not established here. Commit,
decommit, and batch flags currently carry no additional policy, matching that
reference. Statistics report cached blocks as zero because there is no
separate cached-block allocator. Memory types and GPU protection bits are
retained as metadata; host cache policy is unchanged.

These checks establish memory behavior, not an FPS improvement or a new game
compatibility milestone.
