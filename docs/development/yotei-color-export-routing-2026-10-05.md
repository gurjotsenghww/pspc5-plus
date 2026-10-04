# Yōtei: color export masks and attachment routing

The renderer previously used `CB_TARGET_MASK` but ignored `CB_SHADER_MASK` when
choosing writable attachment channels. It also treated an EXP MRT index as the
physical attachment number. With compact exports and gaps between attachments,
this could select the wrong output location, component mapping or integer type.

The renderer now intersects the two channel masks before applying component
swizzles. A disabled packed 11/11/10 UNORM attachment no longer rejects the whole
draw solely because its retained state enables blending. An active packed
attachment still rejects unsupported blending; packed UNORM is not reinterpreted
as floating point.

Complete export interfaces pair the nonzero export formats with the enabled
physical slots in order. The translator receives a location for each compact
export and selects the destination attachment's type and component mapping.
Packing formats remain indexed by the compact export. Incomplete legacy or
synthetic interfaces retain the direct mapping. An explicitly written zero
shader mask disables color writes; an unwritten register retains compatibility
defaults. The draw reuse key includes shader mask, export formats and attachment
component mappings.

Local SharpEmu code helped identify the missing routing step. The implementation
was independently checked against AMD/Mesa's [compacted EXP emission](https://github.com/mirror/mesa/blob/mesa-24.3.0/src/amd/common/ac_nir_lower_ps.c)
and [color-output register emission](https://github.com/mirror/mesa/blob/mesa-24.3.0/src/amd/vulkan/radv_cmd_buffer.c).
The latter compacts `SPI_SHADER_COL_FORMAT` while preserving physical slots in
`CB_SHADER_MASK`. No external implementation was copied.

## Native validation

Six ReleaseSafe Vulkan probes pass with Khronos synchronization validation and
no VUID or synchronization errors: `--packed-unorm`, `--integer-colors`,
`--fragment-coverage`, `--depth-only`, `--srgb-color` and `--mipped-color`.

The expanded color probe checks:

- Masked packed blending preserves pixels and the attachment content epoch,
  while another integer attachment receives a changed value.
- Re-enabling the packed output still reports `UnsupportedColorTarget`.
- Partial shader masks preserve the other channels, and explicit zero preserves
  all color channels.
- Two compact exports write physical slots 0 and 2 with different packing
  formats, while slots 1 and 3 remain unchanged.
- Moving the second export to slot 3 changes its destination correctly;
  restoring the earlier mapping reuses the existing pipeline.

These tests establish the tested rendering semantics. They do not yet establish
a Yōtei frame-rate improvement or correction of every post-tree artifact.

## Compiler experiments

An isolated compiler probe now accepts `--probe-spv-no-opt`. The flag affects
only that probe, which neither dispatches the module nor uses an application
pipeline cache. Runtime compilation policy is unchanged.

Fresh compiler-only fixtures differ only in an undispatched diagnostic PC tag
to avoid the driver's implicit warm cache. Normal compilation takes 39,448 ms
and peaks at 3,364,999,168 private bytes; disabling optimization takes 39,187 ms
and 3,366,584,320 bytes. This does not demonstrate a useful improvement.

A separate, unshipped translator experiment shares the FLAT fault-report body.
The controlled 512-invocation/spilled-LDS fixture shrinks from 3,414,952 to
3,293,340 bytes, but `DontInline` increases pipeline creation to 54,614 ms,
with 3,148,525,568 private bytes. Allowing inlining takes 39,890 ms and
3,375,259,648 bytes. Neither variant is installed. These are compiler stress
fixtures, not exact live dispatches or gameplay FPS measurements.

## Live validation

The preceding runtime-table build measured 37 presented frames in 30.049 seconds
(1.231 FPS) at the tree. Its later repeat was deliberately stopped by the memory
guard with about 374 MiB of system commit headroom. Character control was not
confirmed. A separate live repeat is required for the color-routing change.
