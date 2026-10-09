// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Decoder for `naps_pkg_layout.dat` (PackageLayout_NAPS).
//!
//! Layout matches the public PS5 debug-package description: a 16-byte
//! packed header, then outer-block digests, shuffle patterns, per-file
//! uncompressed offsets, u2c entries, and 9-byte CblockInfo records.

const std = @import("std");

pub const header_size: usize = 16;
pub const outer_stride: usize = 8;
pub const shuffle_stride: usize = 8;
pub const file_offset_stride: usize = 6;
pub const u2c_stride: usize = 10;
pub const cblock_stride: usize = 9;
pub const ublock_size: u64 = 0x40000;
pub const chunk_128k: u32 = 0x20000;

pub const Error = error{
    TruncatedNaps,
    InvalidNaps,
};

pub const Counts = struct {
    num_files: u32,
    compression_type: u8,
    num_keys: u32,
    num_shuffle: u32,
    num_ublocks: u32,
    num_outer_blocks: u32,
    num_cblock_info: u32,

    pub fn numU2c(self: Counts) u32 {
        return (self.num_ublocks + 8) >> 3;
    }

    pub fn numFileOffsets(self: Counts) u32 {
        // The count includes the terminal mount-size entry (type 0x40).
        return self.num_files;
    }
};

pub const FileOffset = struct {
    kind: u8,
    uncompressed_offset: u64,
};

pub const CblockInfo = struct {
    is_run_base: bool,
    coffset_mod: u32,
    uoffset_start: u32,
    clen_even_minus1: u32,
    kde_predictor: u8,
    shuffle_idx: u8,
    tweak_idx_start: u32,
    key_table_idx: u8,
    coffset_start_256k: u32,

    pub fn evenComp(self: CblockInfo) u32 {
        return self.clen_even_minus1 + 1;
    }

    pub fn kraken(self: CblockInfo) bool {
        return self.kde_predictor & 2 != 0;
    }

    pub fn krakenFlags(self: CblockInfo) u32 {
        return @as(u32, self.kde_predictor) | (@as(u32, self.shuffle_idx) << 4);
    }

    /// Runs encode twice the physical 256 KiB block index. The following
    /// data record supplies the byte offset within that block.
    pub fn runOnDisk(self: CblockInfo, first: CblockInfo) u64 {
        return @as(u64, self.coffset_start_256k / 2) * ublock_size + first.coffset_mod;
    }
};

pub const Layout = struct {
    counts: Counts,
    file_offsets: []FileOffset,
    cblocks: []CblockInfo,

    pub fn deinit(self: Layout, allocator: std.mem.Allocator) void {
        allocator.free(self.file_offsets);
        allocator.free(self.cblocks);
    }

    /// The terminal entry. Earlier file boundaries can carry the same kind.
    pub fn mountSize(self: Layout) u64 {
        var index = self.file_offsets.len;
        while (index > 0) {
            index -= 1;
            const entry = self.file_offsets[index];
            if (entry.kind == 0x40) return entry.uncompressed_offset;
        }
        return 0;
    }

    pub fn nextBoundary(self: Layout, cur: u64, mount: u64) u64 {
        var best: u64 = mount;
        for (self.file_offsets) |entry| {
            if (entry.uncompressed_offset > cur and entry.uncompressed_offset <= mount and entry.uncompressed_offset < best) {
                best = entry.uncompressed_offset;
            }
        }
        return best;
    }
};

pub fn decodeHeader(header: []const u8) Error!Counts {
    if (header.len < header_size) return error.TruncatedNaps;
    const word0 = std.mem.readInt(u64, header[0..8], .little);
    const word1 = std.mem.readInt(u64, header[8..16], .little);
    const num_cblock = @as(u32, @truncate(word1 >> 24)) & 0xFFFFFF;
    return .{
        .num_files = (@as(u32, @truncate(word0)) & 0xFFFFFF) + 1,
        .compression_type = @truncate((word0 >> 24) & 3),
        .num_keys = (@as(u32, @truncate(word0 >> 26)) & 3) + 1,
        .num_shuffle = @truncate((word0 >> 28) & 0xF),
        .num_ublocks = @truncate((word0 >> 32) & 0xFFFFFF),
        .num_outer_blocks = @as(u32, @truncate(word1)) & 0xFFFFFF,
        .num_cblock_info = num_cblock + 2,
    };
}

pub fn decodeCblock(raw: []const u8) Error!CblockInfo {
    if (raw.len < cblock_stride) return error.TruncatedNaps;
    var lo: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) lo |= @as(u64, raw[i]) << @intCast(8 * i);
    const hi: u64 = raw[8];
    const is_run = (lo >> 18) & 1 != 0;
    const coff: u32 = @truncate(lo & 0x3FFFF);
    if (!is_run) {
        return .{
            .is_run_base = false,
            .coffset_mod = coff,
            .uoffset_start = @truncate((lo >> 20) & 0x3FFFF),
            .clen_even_minus1 = @truncate((lo >> 38) & 0x1FFFF),
            .kde_predictor = @truncate((lo >> 56) & 7),
            .shuffle_idx = @truncate((lo >> 59) & 0xF),
            .tweak_idx_start = 0,
            .key_table_idx = 0,
            .coffset_start_256k = 0,
        };
    }
    return .{
        .is_run_base = true,
        .coffset_mod = coff,
        .uoffset_start = 0,
        .clen_even_minus1 = 0,
        .kde_predictor = 0,
        .shuffle_idx = 0,
        .tweak_idx_start = @truncate((lo >> 19) & 0xFFFFFFF),
        .key_table_idx = @truncate((lo >> 47) & 3),
        .coffset_start_256k = @truncate(((lo >> 49) & 0x7FFF) | ((hi & 0x1FF) << 15)),
    };
}

fn hasAdjacentRuns(blob: []const u8, u2c_pos: usize, counts: Counts) bool {
    const num_u2c_bytes = @as(usize, counts.numU2c()) * u2c_stride;
    const cbi_pos = std.mem.alignForward(usize, u2c_pos + num_u2c_bytes, 8);
    const total_cblocks = counts.num_cblock_info;
    const check_n = @min(total_cblocks, 64);
    if (cbi_pos >= blob.len) return false;
    const avail_n = @min(check_n, (blob.len - cbi_pos) / cblock_stride);
    var last_was_run = false;
    var i: usize = 0;
    while (i < avail_n) : (i += 1) {
        const rec = blob[cbi_pos + i * cblock_stride ..][0..cblock_stride];
        const is_run = (decodeCblock(rec) catch return true).is_run_base;
        if (is_run and last_was_run) return true;
        last_was_run = is_run;
    }
    return false;
}

fn detectU2cOffset(blob: []const u8, pos: usize, counts: Counts) usize {
    const pos_unaligned = pos;
    const pos_aligned = std.mem.alignForward(usize, pos, 16);
    if (pos_unaligned == pos_aligned) return pos_unaligned;
    if (hasAdjacentRuns(blob, pos_aligned, counts)) {
        return pos_unaligned;
    }
    return pos_aligned;
}

pub fn parse(allocator: std.mem.Allocator, blob: []const u8) Error!Layout {
    const counts = try decodeHeader(blob);
    const fidx_n = counts.numFileOffsets();

    const map_end = sectionEnd(blob, counts, fidx_n);
    if (blob.len < map_end) return error.TruncatedNaps;

    var pos: usize = header_size;
    pos += @as(usize, counts.num_outer_blocks) * outer_stride;
    pos += @as(usize, counts.num_shuffle) * shuffle_stride;

    if (pos + fidx_n * file_offset_stride > blob.len) return error.TruncatedNaps;
    const file_offsets = allocator.alloc(FileOffset, fidx_n) catch return error.TruncatedNaps;
    errdefer allocator.free(file_offsets);
    var i: usize = 0;
    while (i < fidx_n) : (i += 1) {
        const rec = blob[pos + i * file_offset_stride ..][0..file_offset_stride];
        var off: u64 = 0;
        var b: usize = 0;
        while (b < 5) : (b += 1) off |= @as(u64, rec[b]) << @intCast(8 * b);
        file_offsets[i] = .{ .kind = rec[5], .uncompressed_offset = off };
    }
    pos += fidx_n * file_offset_stride;

    pos = detectU2cOffset(blob, pos, counts);
    pos += @as(usize, counts.numU2c()) * u2c_stride;
    pos = std.mem.alignForward(usize, pos, 8);

    if (pos + @as(usize, counts.num_cblock_info) * cblock_stride > blob.len) return error.TruncatedNaps;
    const cblocks = allocator.alloc(CblockInfo, counts.num_cblock_info) catch return error.TruncatedNaps;
    errdefer allocator.free(cblocks);
    i = 0;
    while (i < counts.num_cblock_info) : (i += 1) {
        const rec_off = pos + i * cblock_stride;
        cblocks[i] = try decodeCblock(blob[rec_off..][0..cblock_stride]);
    }

    return .{ .counts = counts, .file_offsets = file_offsets, .cblocks = cblocks };
}

fn sectionEnd(blob: []const u8, counts: Counts, fidx_n: usize) usize {
    var pos = header_size + @as(usize, counts.num_outer_blocks) * outer_stride;
    pos += @as(usize, counts.num_shuffle) * shuffle_stride;
    pos += fidx_n * file_offset_stride;
    pos = detectU2cOffset(blob, pos, counts);
    pos += @as(usize, counts.numU2c()) * u2c_stride;
    pos = std.mem.alignForward(usize, pos, 8);
    return pos + @as(usize, counts.num_cblock_info) * cblock_stride;
}

test "decodeHeader reads packed naps fields" {
    var header: [16]u8 = @splat(0);
    // numFiles-1=63, comp=2, keys-1=0, shuffle=0, ublocks=40808
    const word0: u64 = 63 | (@as(u64, 2) << 24) | (@as(u64, 40808) << 32);
    // outer=68506, cblock-2=43579
    const word1: u64 = 68506 | (@as(u64, 43579) << 24);
    std.mem.writeInt(u64, header[0..8], word0, .little);
    std.mem.writeInt(u64, header[8..16], word1, .little);
    const counts = try decodeHeader(&header);
    try std.testing.expectEqual(@as(u32, 64), counts.num_files);
    try std.testing.expectEqual(@as(u8, 2), counts.compression_type);
    try std.testing.expectEqual(@as(u32, 40808), counts.num_ublocks);
    try std.testing.expectEqual(@as(u32, 68506), counts.num_outer_blocks);
    try std.testing.expectEqual(@as(u32, 43581), counts.num_cblock_info);
}

test "decodeCblock distinguishes std and run-base" {
    var std_rec: [9]u8 = @splat(0);
    // coff=20, not run
    std_rec[0] = 1;
    const std_info = try decodeCblock(&std_rec);
    try std.testing.expectEqual(false, std_info.is_run_base);
    try std.testing.expectEqual(@as(u32, 1), std_info.coffset_mod);

    var run_rec: [9]u8 = @splat(0);
    run_rec[2] = 0x14; // run bit 18, tweak 2
    const run_info = try decodeCblock(&run_rec);
    try std.testing.expectEqual(true, run_info.is_run_base);
    try std.testing.expectEqual(@as(u32, 2), run_info.tweak_idx_start);
    var first = std_info;
    first.coffset_mod = 0x10000;
    try std.testing.expectEqual(@as(u64, 0x10000), run_info.runOnDisk(first));
}

test "NAPS padding does not become file offsets or shift CblockInfo" {
    var blob: [96]u8 = @splat(0);
    // Two fidx entries, one outer block, one ublock and two CblockInfo records.
    std.mem.writeInt(u64, blob[0..8], 1 | (@as(u64, 1) << 32), .little);
    std.mem.writeInt(u64, blob[8..16], 1, .little);
    // Outer digests end at 24 and fidx follows without padding.
    blob[32] = 4; // mount size 0x40000 in the second 40-bit offset
    blob[35] = 0x40;
    // fidx ends at 36, u2c occupies 48..58, cblocks start at 64.
    blob[66] = 4; // run marker: bit 18, not bit 2
    var layout = try parse(std.testing.allocator, &blob);
    defer layout.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), layout.file_offsets.len);
    try std.testing.expectEqual(@as(u64, 0x40000), layout.mountSize());
    try std.testing.expect(layout.cblocks[0].is_run_base);
    try std.testing.expect(!layout.cblocks[1].is_run_base);
    try std.testing.expectError(error.TruncatedNaps, parse(std.testing.allocator, blob[0..81]));
}

test "NAPS preserves the high bit of the first Kraken chunk length" {
    const rec = try decodeCblock(&.{ 0x09, 0x72, 0xa1, 0x48, 0x0e, 0xe2, 0xc9, 0x12, 0x00 });
    try std.testing.expect(!rec.is_run_base);
    try std.testing.expectEqual(@as(u32, 75657), rec.evenComp());
    try std.testing.expectEqual(@as(u32, 0x22), rec.krakenFlags());
    const stored = try decodeCblock(&.{ 0x0a, 0x00, 0xa2, 0x24, 0xc3, 0xff, 0xff, 0x04, 0x00 });
    try std.testing.expectEqual(@as(u32, 0x20000), stored.evenComp());
}

test "CblockInfo starts after 8-byte u2c padding even when not 16-byte aligned" {
    var blob: [96]u8 = @splat(0);
    // Two file offsets, one outer digest, nine ublocks: two u2c entries.
    std.mem.writeInt(u64, blob[0..8], 1 | (@as(u64, 9) << 32), .little);
    std.mem.writeInt(u64, blob[8..16], 1, .little);
    blob[32] = 0x24; // terminal mount size 0x240000
    blob[35] = 0x40;
    // fidx ends at 36, u2c occupies 48..68. CblockInfo starts at 72,
    // not 80; optional padding after its two records is not another record.
    blob[74] = 4; // run-base marker
    blob[81] = 10; // first data record's compressed offset
    for ([_]usize{ 90, blob.len }) |len| {
        var layout = try parse(std.testing.allocator, blob[0..len]);
        defer layout.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(u64, 0x240000), layout.mountSize());
        try std.testing.expectEqual(@as(usize, 2), layout.cblocks.len);
        try std.testing.expect(layout.cblocks[0].is_run_base);
        try std.testing.expect(!layout.cblocks[1].is_run_base);
        try std.testing.expectEqual(@as(u64, 10), layout.cblocks[0].runOnDisk(layout.cblocks[1]));
    }
    try std.testing.expectError(error.TruncatedNaps, parse(std.testing.allocator, blob[0..89]));
}

test "inspect WALL-E package naps layout" {
    const pkg_path = "D:\\PS5-TG\\[SuperPSX]-Disney.Pixar.WALL-E-PPSA14383 – USA-Game (v01.000.001)(4.xx BackPort)-FPKG-PS5.pkg";
    var file = std.Io.Dir.cwd().openFile(std.testing.io, pkg_path, .{ .mode = .read_only }) catch return;
    defer file.close(std.testing.io);
    const flen = try file.length(std.testing.io);

    var header: [0x100]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &header, 0);
    const root = @import("root.zig");
    const fih = try root.parseFih(&header, flen);

    var sb_buf: [0x400]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &sb_buf, fih.superblock_offset);
    const sb = try root.pfs.parseSuperblock(&sb_buf, 0);

    const inodes = try root.pfs.loadInodes(file, std.testing.io, std.testing.allocator, fih.pfs_offset, sb);
    defer std.testing.allocator.free(inodes);

    const naps_blob = (root.pfs.loadNamedOuter(file, std.testing.io, std.testing.allocator, fih.pfs_offset, sb, inodes, "naps_pkg_layout.dat")).?;
    defer std.testing.allocator.free(naps_blob);

    var layout = try parse(std.testing.allocator, naps_blob);
    defer layout.deinit(std.testing.allocator);

    var blocks: std.ArrayList(root.inner.UBlock) = .empty;
    defer blocks.deinit(std.testing.allocator);
    try root.inner.walkBlocks(std.testing.allocator, layout, layout.mountSize(), &blocks);

    const meta_base_logical = blk: {
        var best: u64 = 0;
        for (layout.file_offsets) |entry_fo| {
            if (entry_fo.uncompressed_offset > 0 and entry_fo.uncompressed_offset < layout.mountSize() and entry_fo.uncompressed_offset > best) {
                best = entry_fo.uncompressed_offset;
            }
        }
        break :blk best;
    };

    const image = try root.pfs.findPfsImage(inodes, file, std.testing.io, fih.pfs_offset, sb);
    const image_offset = fih.pfs_offset + @as(u64, @intCast(image.startBlock())) * sb.block_size;
    const image_size = image.size;

    const meta = try root.inner.decodeTail(std.testing.allocator, file, std.testing.io, image_offset, image_size, blocks.items, meta_base_logical);
    defer std.testing.allocator.free(meta.buf);

    const sb_off = root.inner.findSuperblock(meta.buf, layout.mountSize()).?;
    try std.testing.expectEqual(@as(usize, 0), sb_off);

    const files = try root.inner.readFileTree(std.testing.allocator, file, std.testing.io, image_offset, image_size, blocks.items, meta.buf, meta.logical_base, sb_off);
    defer {
        for (files) |f| std.testing.allocator.free(f.path);
        std.testing.allocator.free(files);
    }
    try std.testing.expect(files.len > 0);

    var eboot_file: ?root.inner.MappedFile = null;
    for (files) |f| {
        if (std.mem.eql(u8, f.path, "eboot.bin")) {
            eboot_file = f;
            break;
        }
    }
    const eb = eboot_file.?;
    const eboot_buf = try std.testing.allocator.alloc(u8, @intCast(eb.size));
    defer std.testing.allocator.free(eboot_buf);
    try root.inner.copyLogical(file, std.testing.io, std.testing.allocator, image_offset, image_size, blocks.items, eb.logical, eboot_buf);

    const magic = std.mem.readInt(u32, eboot_buf[0..4], .little);
    try std.testing.expectEqual(@as(u32, 0x1d3d154f), magic);
    const elf_off = root.pfs.self_elf_offset;
    try std.testing.expectEqualStrings("\x7fELF", eboot_buf[elf_off..][0..4]);
}

