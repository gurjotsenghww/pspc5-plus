// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! A conservative filter for newer writes to overlapping buffer views. A
//! positive result requires the caller to inspect the resident allocations.
const std = @import("std");

pub fn History(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Write = struct { address: u64, size: u64, sequence: u64 };
        writes: [capacity]Write = undefined,
        next: usize = 0,
        count: usize = 0,

        pub fn record(self: *Self, address: u64, size: u64, sequence: u64) void {
            self.writes[self.next] = .{ .address = address, .size = size, .sequence = sequence };
            self.next = (self.next + 1) % capacity;
            self.count = @min(self.count + 1, capacity);
        }

        pub fn mayOverlapSince(self: *const Self, address: u64, size: u64, sequence: u64) bool {
            if (self.count == 0 or size == 0) return false;
            // Missing history must never certify a stale backing as current.
            if (self.count == capacity and sequence < self.writes[self.next].sequence) return true;
            var cursor = self.next;
            for (0..self.count) |_| {
                cursor = (cursor + capacity - 1) % capacity;
                const write = self.writes[cursor];
                if (write.sequence <= sequence) return false;
                if (write.address < address +| size and address < write.address +| write.size) return true;
            }
            return false;
        }
    };
}

test "buffer write history handles nested ranges and half-open boundaries" {
    var history = History(4){};
    try std.testing.expect(!history.mayOverlapSince(0x1000, 128, 0));
    history.record(0x1020, 64, 3);
    try std.testing.expect(history.mayOverlapSince(0x1000, 128, 2));
    try std.testing.expect(history.mayOverlapSince(0x1040, 4, 2));
    try std.testing.expect(!history.mayOverlapSince(0x1000, 128, 3));
    try std.testing.expect(!history.mayOverlapSince(0x1000, 32, 2));
    try std.testing.expect(!history.mayOverlapSince(0x1060, 32, 2));
    try std.testing.expect(!history.mayOverlapSince(0x1040, 0, 2));
}

test "buffer write history cannot hide an overlap after ring rollover" {
    var history = History(4){};
    history.record(0x1020, 64, 1);
    for (2..12) |sequence| history.record(0x2000, 64, sequence);
    try std.testing.expect(history.mayOverlapSince(0x1000, 128, 0));
    try std.testing.expect(!history.mayOverlapSince(0x1000, 128, 8));
    try std.testing.expect(history.mayOverlapSince(0x2000, 128, 10));
    try std.testing.expect(!history.mayOverlapSince(0x2000, 128, 11));
}
