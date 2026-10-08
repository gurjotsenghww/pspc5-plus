// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Queries on large static bitsets must borrow their backing words. Zig's
//! ArrayBitSet.isSet takes Self by value; an out-of-line query can copy several
//! KiB just to inspect one bit in a shader/resource hot loop.
const std = @import("std");

pub inline fn contains(bits: anytype, index: usize) bool {
    const Set = @typeInfo(@TypeOf(bits)).pointer.child;
    const word_bits = @bitSizeOf(Set.MaskInt);
    std.debug.assert(index < bits.capacity());
    return bits.masks[index / word_bits] & (@as(Set.MaskInt, 1) << @intCast(index % word_bits)) != 0;
}

test "borrowed bitset queries preserve word boundaries and partial final words" {
    inline for (.{ 65, 512, 8192, 16384, 65536 }) |capacity| {
        var bits = std.StaticBitSet(capacity).initEmpty();
        for (0..capacity) |index| {
            if (index % 7 == 0 or index == capacity - 1) bits.set(index);
        }
        for (0..capacity) |index|
            try std.testing.expectEqual(index % 7 == 0 or index == capacity - 1, contains(&bits, index));
        bits.unset(capacity - 1);
        try std.testing.expect(!contains(&bits, capacity - 1));
    }
}
