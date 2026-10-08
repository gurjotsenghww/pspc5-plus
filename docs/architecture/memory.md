# `memory` — guest address space

[← Documentation index](../README.md) · [Project status](../project-status.md)

Guest x86-64 code executes natively and contains absolute addresses. Relocating
the whole process to an arbitrary host allocation is therefore not an option: a
guest address must be the same numeric address in the host process.

[src/memory/root.zig](../../src/memory/root.zig) reserves the native layout before a
module is loaded. The documented inclusive ranges correspond to these half-open
intervals in the implementation:

| Area | Guest range | Size |
|---|---:|---:|
| System managed | `0x00_0004_0000 .. 0x07_FFFF_C000` | just under 32 GiB |
| System reserved | `0x08_0000_0000 .. 0x0F_C000_0000` | 31 GiB |
| Device | `0x0F_E000_0000 .. 0x0F_F000_0000` | 256 MiB |
| User (Windows/Linux) | `0x10_0000_0000 .. 0xFC_0000_0000` | 944 GiB |
| User (macOS) | `0x70_0000_0000 .. 0xFC_0000_0000` | 560 GiB |

These are reservations, not allocations of physical RAM. Pages are committed
in 16 KiB units only when `mapFixed` or `map` creates a guest mapping. `unmap`
decommits those pages while retaining the outer reservation, so the same guest
address cannot be taken by an unrelated host allocation between uses.

Direct memory is different from a private mapping: its physical offset has a
stable identity. [src/memory/backing_store.zig](../../src/memory/backing_store.zig)
provides one sparse shared object for the pool, and mappings of the same offset
are coherent aliases. Writing through one guest virtual address is immediately
visible through every other address mapped to those physical pages. The pool's
capacity remains virtual; mapped pages consume backing/commit resources, and
physical working-set pages are faulted on first touch.

An explicit fixed direct-memory request retains its host views when the guest
address, complete size, physical offset and CPU permissions match one existing
mapping exactly. This avoids repeated unmap, placeholder splitting, view and
commit calls, and preserves GPU page observations of the unchanged storage.
No-overwrite requests still reject occupied ranges. Changed backing, changed
permissions, partial ranges and fragmented mapping metadata follow the normal
replacement path; requested names and GPU access bits are still updated.

Direct and flexible memory are cut from one supply of a little under 13.5 GiB,
which is what the console leaves a title after the system takes its share, so
the direct pool is what remains once the flexible budget is set aside. Reporting
the two independently would promise more memory than the console has, and a
title sizes its allocators from both answers during startup — which is exactly
when it would budget for memory that was never going to exist.

`sceKernelMemoryPoolExpand` donates 64 KiB physical blocks from that same direct
budget. `MemoryPoolReserve` claims virtual arenas in 2 MiB units; committing an
arena attaches donated blocks, including fragmented physical spans, to one
contiguous virtual range. Committed pool pages use the existing shared backing
and GPU page tracking, with pool ownership retained separately in mapping
metadata. Virtual queries report pooled/reserved or pooled/committed state and
do not expose the internal direct-memory offset. Flexible-memory usage is
unchanged.

Decommit retains the virtual reservation and returns its physical blocks to
the pool. Shared backing preserves data when those blocks are reused. Ordinary
unmap also returns committed blocks; physical release rejects donations still
in use. Mapping and decommit operations preflight complete ranges and reserve
interval storage before changing host pages. The implementation and its
remaining batch-operation limitation are documented in the
[MemoryPool report](../development/memory-pool-2026-10-08.md).

Windows has permanent low-address mappings, notably `KUSER_SHARED_DATA`, inside
the system-managed window. A single `VirtualAlloc` reservation would therefore
fail even though almost the whole window is free. Initialization scans with
`VirtualQuery` and reserves every free extent as a placeholder at its exact
address. Private and unaligned mappings retain 16 KiB placeholder/view
boundaries. Fully aligned direct-memory mappings use 64 KiB Windows section
views instead, matching the host allocation granularity and avoiding four
separate view/commit operations per group of guest pages. Views are restored
as placeholders and coalesced on unmap, while mapping metadata and protection
remain accurate at 16 KiB guest-page boundaries. A requested mapping that lands
in a host-owned hole fails explicitly. Linux uses
`MAP_FIXED_NOREPLACE`; macOS uses a non-destructive fixed hint and rejects a
result returned at any other address. No path uses a `MAP_FIXED` operation that
could overwrite an unrelated host mapping.

Committing inside a guest reservation queries the current Windows placeholder
boundaries before splitting the host views. A later nearby reservation may
coalesce the earlier reservation's uncommitted tail with free space without
changing its guest metadata. Assuming both boundaries still match caused a
16 KiB direct-memory map to fail with `CONFLICTING_ADDRESSES` during Cat Quest
III loading. A regression fills that tail after reserving a separate neighbor
and verifies that the neighbor and intervening gap retain their guest state.

The shared direct-memory backend is a page-file section with `SEC_RESERVE` on
Windows, a sparse `memfd` on Linux, and an immediately unlinked POSIX shared
memory object on macOS. Section/file views replace only ranges already owned by
the address space. Teardown restores the reservation before closing the backing
object.

The address-space API also owns the sorted mapping table. Loader segments,
private allocations, direct-memory mappings, flexible-memory mappings, and
metadata-only virtual reservations all go through it, so overlap checks, page
protections, names, and memory queries cannot disagree between subsystems.
Partial protection, metadata, and unmap operations split table entries at exact
16 KiB boundaries. Reads and writes validate the complete committed range
before dereferencing the identity-mapped pointer.

Optional GPU page tracking protects writable source pages until their next CPU
write and records a generation for each page. Its protection lookup uses the
containing mapping in the sorted table and checks the upper bound before
subtracting the page address. This prevents a later writable allocation from
inheriting an earlier module's permissions through unsigned underflow, and
avoids scanning every earlier mapping for each tracked page. Tests cover gaps,
reserved ranges, full-page boundaries and writes to a later allocation with
different permissions. Native rendering and performance still require
title-specific verification; see the [Big Helmet Heroes watch measurements](../development/big-helmet-heroes-page-watches-2026-09-29.md).

On Windows, adjacent unarmed pages in suitable direct-memory mappings can
share one protection call within a 64 KiB granule. Each group is bounded by a
fresh native-region query, so it cannot cross separately mapped views or a
protection split. Private and unaligned mappings keep individual page calls.
This changes protection calls only; host view sizes are unchanged.

A group is marked armed only after host protection succeeds. Native fault
handlers share the tracker lock, and generations remain per page. HLE writes
restore groups only when their saved logical rights agree; native faults
still restore one page. All entries in a group are allocated before its
protection changes. A rejected grouped operation retries one page without
claiming the remainder.
Tests exercise aligned and remapped views, mixed rights, individual write
faults, generation invalidation and the grouped-operation fallback.

---
