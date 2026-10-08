// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Basic GPOS pair advances for fonts whose `kern` feature also contains
//! contextual lookups. FreeType's optional GPOS reader rejects that mixture.
//! This pair API intentionally does not perform contextual shaping. All
//! offsets remain within bounded slices, including collection face offsets.
const std = @import("std");
const Invalid = error{InvalidTable};
const Table = struct {
    bytes: []const u8,
    fn at(self: Table, offset: usize) Invalid!Table {
        if (offset > self.bytes.len) return error.InvalidTable;
        return .{ .bytes = self.bytes[offset..] };
    }
    fn word(self: Table, offset: usize) Invalid!u16 {
        if (offset > self.bytes.len or self.bytes.len - offset < 2) return error.InvalidTable;
        return std.mem.readInt(u16, self.bytes[offset..][0..2], .big);
    }
    fn dword(self: Table, offset: usize) Invalid!u32 {
        if (offset > self.bytes.len or self.bytes.len - offset < 4) return error.InvalidTable;
        return std.mem.readInt(u32, self.bytes[offset..][0..4], .big);
    }
    fn signedWord(self: Table, offset: usize) Invalid!i16 {
        return @bitCast(try self.word(offset));
    }
};

pub fn findGpos(data: []const u8) ?[]const u8 {
    return find(data) catch null;
}
fn find(data: []const u8) Invalid!?[]const u8 {
    const file = Table{ .bytes = data };
    const face = if (try file.dword(0) == 0x74746366) blk: {
        if (try file.dword(8) == 0) return error.InvalidTable;
        break :blk try file.at(try file.dword(12));
    } else file;
    const count = try face.word(4);
    for (0..count) |i| {
        const record = try face.at(12 + i * 16);
        if (try record.dword(0) != 0x47504f53) continue;
        const table = try file.at(try record.dword(8));
        const length = try record.dword(12);
        if (length > table.bytes.len) return error.InvalidTable;
        return table.bytes[0..length];
    }
    return null;
}

pub fn advance(data: []const u8, left: u32, right: u32) i32 {
    return parse(.{ .bytes = data }, left, right) catch 0;
}
fn parse(gpos: Table, left: u32, right: u32) Invalid!i32 {
    if (try gpos.word(0) != 1) return error.InvalidTable;
    const features = try gpos.at(try gpos.word(6));
    const lookups = try gpos.at(try gpos.word(8));
    const lookup_count = try lookups.word(0);
    var selected = [_]u64{0} ** 1024;
    for (0..try features.word(0)) |i| {
        const record = try features.at(2 + i * 6);
        if (try record.dword(0) != 0x6b65726e) continue;
        const feature = try features.at(try record.word(4));
        for (0..try feature.word(2)) |j| {
            const index = try feature.word(4 + j * 2);
            if (index >= lookup_count) return error.InvalidTable;
            selected[index / 64] |= @as(u64, 1) << @as(u6, @truncate(index));
        }
    }
    var result: i32 = 0;
    for (0..lookup_count) |i| {
        if (selected[i / 64] & (@as(u64, 1) << @as(u6, @truncate(i))) == 0) continue;
        const lookup = try lookups.at(try lookups.word(2 + i * 2));
        const kind = try lookup.word(0);
        if (kind != 2 and kind != 9) continue;
        for (0..try lookup.word(4)) |j| {
            var subtable = try lookup.at(try lookup.word(6 + j * 2));
            if (kind == 9) {
                if (try subtable.word(0) != 1 or try subtable.word(2) != 2) continue;
                subtable = try subtable.at(try subtable.dword(4));
            }
            if (try pair(subtable, left, right)) |value| {
                result += value;
                break;
            }
        }
    }
    return result;
}
fn coverage(table: Table, glyph: u32) Invalid!?u32 {
    const count = try table.word(2);
    switch (try table.word(0)) {
        1 => {
            var lo: usize = 0;
            var hi: usize = count;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const value = try table.word(4 + mid * 2);
                if (value == glyph) return @intCast(mid);
                if (value < glyph) lo = mid + 1 else hi = mid;
            }
        },
        2 => for (0..count) |i| {
            const record = try table.at(4 + i * 6);
            const start = try record.word(0);
            const end = try record.word(2);
            if (start > end) return error.InvalidTable;
            if (glyph >= start and glyph <= end) return @as(u32, try record.word(4)) + glyph - start;
        },
        else => return error.InvalidTable,
    }
    return null;
}
fn class(table: Table, glyph: u32) Invalid!u16 {
    switch (try table.word(0)) {
        1 => {
            const start = try table.word(2);
            const count = try table.word(4);
            if (glyph < start or glyph - start >= count) return 0;
            return table.word(6 + (glyph - start) * 2);
        },
        2 => for (0..try table.word(2)) |i| {
            const record = try table.at(4 + i * 6);
            const start = try record.word(0);
            const end = try record.word(2);
            if (start > end) return error.InvalidTable;
            if (glyph >= start and glyph <= end) return record.word(4);
        },
        else => return error.InvalidTable,
    }
    return 0;
}
fn pair(table: Table, left: u32, right: u32) Invalid!?i16 {
    // Only an xAdvance for the first glyph is a simple kerning pair. Position,
    // device, mark and contextual adjustments belong to a shaping API.
    if (try table.word(4) != 4 or try table.word(6) != 0) return null;
    const covered = try coverage(try table.at(try table.word(2)), left) orelse return null;
    switch (try table.word(0)) {
        1 => {
            if (covered >= try table.word(8)) return error.InvalidTable;
            const pairs = try table.at(try table.word(10 + @as(usize, covered) * 2));
            var lo: usize = 0;
            var hi: usize = try pairs.word(0);
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const value = try pairs.word(2 + mid * 4);
                if (value == right) return try pairs.signedWord(4 + mid * 4);
                if (value < right) lo = mid + 1 else hi = mid;
            }
            return null;
        },
        2 => {
            const first = try class(try table.at(try table.word(8)), left);
            const second = try class(try table.at(try table.word(10)), right);
            const rows = try table.word(12);
            const columns = try table.word(14);
            if (first >= rows or second >= columns) return error.InvalidTable;
            return try table.signedWord(16 + (@as(usize, first) * columns + second) * 2);
        },
        else => return null,
    }
}

test "font GPOS pair reader rejects short tables and out-of-range offsets" {
    try std.testing.expectEqual(@as(i32, 0), advance(&.{ 0, 1 }, 1, 2));
    const truncated = [_]u8{ 0, 1, 0, 0, 0, 0, 0xff, 0xff, 0xff, 0xff };
    try std.testing.expectEqual(@as(i32, 0), advance(&truncated, 1, 2));
    try std.testing.expectEqual(null, findGpos("bad font"));
}

test "font GPOS extension pairs deduplicate features and reject every truncation" {
    // One extension lookup, referenced twice by `kern`, with pair 7/8 = -80.
    // Coverage comes last so every truncation must fail without reading past it.
    const words = [_]u16{
        1, 0, 0, 10, 26, // GPOS header
        1, 0x6b65, 0x726e, 8, // feature list / kern record
        0, 2, 0, 0, // feature references lookup zero twice
        1, 4, // lookup list
        9, 0, 1, 8, // extension lookup
        1, 2, 0, 8, // extension format, type, 32-bit offset
        1, 18, 4, 0, 1, 12, // pair format 1
        1, 8, 0xffb0, // one pair
        1, 1, 7, // coverage
    };
    var bytes: [words.len * 2]u8 = undefined;
    for (words, 0..) |word, i| std.mem.writeInt(u16, bytes[i * 2 ..][0..2], word, .big);
    try std.testing.expectEqual(@as(i32, -80), advance(&bytes, 7, 8));
    try std.testing.expectEqual(@as(i32, 0), advance(&bytes, 7, 9));
    try std.testing.expectEqual(@as(i32, 0), advance(&bytes, 6, 8));
    for (0..bytes.len) |length| try std.testing.expectEqual(@as(i32, 0), advance(bytes[0..length], 7, 8));
}
