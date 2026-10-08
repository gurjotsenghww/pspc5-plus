// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Address buckets for resident image views. The caller still checks the
//! complete view and source-generation keys for every candidate.
const std = @import("std");

pub fn Index(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Slot = if (capacity < std.math.maxInt(u16)) u16 else u32;
        const empty = std.math.maxInt(Slot);
        const bucket_count = std.math.ceilPowerOfTwoAssert(usize, @max(16, capacity / 2));
        heads: [bucket_count]Slot = undefined,
        links: [capacity]Slot = undefined,
        valid: bool = false,

        pub const Iterator = struct {
            index: *const Self,
            slot: usize,
            linear_end: usize = 0,

            pub fn next(self: *Iterator) ?usize {
                // Renderer cache limits can exceed the fixed bucket storage.
                // Fall back to the original scan without narrowing the caller's
                // configured capacity or dropping any possible alias.
                if (self.linear_end != 0) {
                    if (self.slot == self.linear_end) return null;
                    const slot = self.slot;
                    self.slot += 1;
                    return slot;
                }
                if (self.slot == empty) return null;
                const slot = self.slot;
                self.slot = self.index.links[slot];
                return slot;
            }
        };

        fn bucket(address: u64) usize {
            var key = address;
            key ^= key >> 33;
            key *%= 0xff51afd7ed558ccd;
            key ^= key >> 33;
            return @intCast(key & (bucket_count - 1));
        }

        pub fn invalidate(self: *Self) void {
            self.valid = false;
        }

        /// Maintain a live index when one cache slot is appended or recycled.
        /// Chains remain sorted so aliases keep the original scan precedence.
        pub fn insert(self: *Self, slot: usize, address: u64) void {
            if (!self.valid) return;
            if (slot >= capacity) return self.invalidate();
            var link = &self.heads[bucket(address)];
            while (link.* != empty and link.* < slot) link = &self.links[link.*];
            self.links[slot] = link.*;
            link.* = @intCast(slot);
        }

        pub fn replace(self: *Self, slot: usize, previous: u64, address: u64) void {
            if (!self.valid) return;
            if (slot >= capacity) return self.invalidate();
            if (bucket(previous) == bucket(address)) return;
            var link = &self.heads[bucket(previous)];
            while (link.* != empty and link.* != slot) link = &self.links[link.*];
            if (link.* == empty) return self.invalidate();
            link.* = self.links[slot];
            self.insert(slot, address);
        }

        pub fn candidates(self: *Self, items: anytype, address: u64) Iterator {
            return self.candidatesBy(items, address, struct {
                fn get(item: @TypeOf(items[0])) u64 {
                    return item.guest_address;
                }
            }.get);
        }

        pub fn candidatesBy(self: *Self, items: anytype, address: u64, comptime addressOf: anytype) Iterator {
            if (items.len > capacity) return .{ .index = self, .slot = 0, .linear_end = items.len };
            if (!self.valid) {
                @memset(&self.heads, empty);
                // Preserve the old ascending scan order when several views
                // share an address or unrelated addresses hash together.
                var slot = items.len;
                while (slot != 0) {
                    slot -= 1;
                    const head = &self.heads[bucket(addressOf(items[slot]))];
                    self.links[slot] = head.*;
                    head.* = @intCast(slot);
                }
                self.valid = true;
            }
            return .{ .index = self, .slot = self.heads[bucket(address)] };
        }
    };
}

test "sampled image buckets preserve collisions and rebuild after ordered removal" {
    const CacheIndex = Index(64);
    const Entry = struct { guest_address: u64 };
    var index = CacheIndex{};
    var collision: u64 = 0x1100;
    while (CacheIndex.bucket(collision) != CacheIndex.bucket(0x1000)) collision += 256;
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(std.testing.allocator);
    for ([_]u64{ 0x1000, collision, 0x1000 }) |address|
        try entries.append(std.testing.allocator, .{ .guest_address = address });
    var candidates = index.candidates(entries.items, 0x1000);
    for (0..3) |slot| try std.testing.expectEqual(@as(?usize, slot), candidates.next());
    try std.testing.expectEqual(null, candidates.next());
    _ = entries.orderedRemove(0);
    index.invalidate();
    candidates = index.candidates(entries.items, 0x1000);
    try std.testing.expectEqual(@as(?usize, 0), candidates.next());
    try std.testing.expectEqual(@as(?usize, 1), candidates.next());
    try std.testing.expectEqual(null, candidates.next());
    entries.clearRetainingCapacity();
    index.invalidate();
    candidates = index.candidates(entries.items, 0x1000);
    try std.testing.expectEqual(null, candidates.next());
    for (0..64) |slot| try entries.append(std.testing.allocator, .{ .guest_address = 0x1000 + slot * 256 });
    index.invalidate();
    for (entries.items, 0..) |entry, wanted| {
        candidates = index.candidates(entries.items, entry.guest_address);
        var found = false;
        while (candidates.next()) |slot| if (slot == wanted) {
            found = true;
        };
        try std.testing.expect(found);
    }
}

test "descriptor address buckets preserve view order after slot replacement" {
    const Entry = struct {
        descriptor: struct { address: u64 },
        valid: bool = true,
        fn address(self: @This()) u64 {
            return self.descriptor.address;
        }
    };
    var entries = [_]Entry{
        .{ .descriptor = .{ .address = 0x1000 } },
        .{ .descriptor = .{ .address = 0x2000 } },
        .{ .descriptor = .{ .address = 0x1000 } },
    };
    var index = Index(64){};
    var candidates = index.candidatesBy(&entries, 0x1000, Entry.address);
    var matched: std.ArrayList(usize) = .empty;
    defer matched.deinit(std.testing.allocator);
    while (candidates.next()) |slot| {
        if (entries[slot].descriptor.address == 0x1000)
            try matched.append(std.testing.allocator, slot);
    }
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, matched.items);
    // Eviction leaves the address in its slot; callers exclude invalid views.
    entries[0].valid = false;
    candidates = index.candidatesBy(&entries, 0x1000, Entry.address);
    matched.clearRetainingCapacity();
    while (candidates.next()) |slot| {
        if (entries[slot].valid and entries[slot].descriptor.address == 0x1000)
            try matched.append(std.testing.allocator, slot);
    }
    try std.testing.expectEqualSlices(usize, &.{2}, matched.items);
    entries[0] = .{ .descriptor = .{ .address = 0x3000 } };
    entries[1].descriptor.address = 0x1000;
    index.invalidate();
    candidates = index.candidatesBy(&entries, 0x1000, Entry.address);
    matched.clearRetainingCapacity();
    while (candidates.next()) |slot| {
        if (entries[slot].descriptor.address == 0x1000)
            try matched.append(std.testing.allocator, slot);
    }
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, matched.items);
}

test "address buckets fall back for oversized caches and recover after invalidation" {
    const Entry = struct { guest_address: u64 };
    var entries: [65]Entry = undefined;
    for (&entries, 0..) |*entry, i| entry.* = .{ .guest_address = 0x1000 + i * 256 };
    var index = Index(64){};
    var candidates = index.candidates(&entries, entries[64].guest_address);
    for (0..entries.len) |slot| try std.testing.expectEqual(@as(?usize, slot), candidates.next());
    try std.testing.expectEqual(null, candidates.next());
    index.invalidate();
    candidates = index.candidates(entries[0..1], entries[0].guest_address);
    try std.testing.expectEqual(@as(?usize, 0), candidates.next());
    try std.testing.expectEqual(null, candidates.next());
}

test "incremental buffer replacements match a rebuilt index under cache churn" {
    const Entry = struct { guest_address: u64 };
    var entries: [64]Entry = undefined;
    var index = Index(64){};
    const empty_entries: []const Entry = entries[0..0];
    _ = index.candidates(empty_entries, 0);
    for (&entries, 0..) |*entry, slot| {
        entry.* = .{ .guest_address = 0x1000 + (slot % 7) * 256 };
        index.insert(slot, entry.guest_address);
    }
    for (0..256) |step| {
        const slot = (step * 13) % entries.len;
        const address = 0x1000 + (step % 19) * 256;
        index.replace(slot, entries[slot].guest_address, address);
        entries[slot].guest_address = address;
        var rebuilt = Index(64){};
        for (entries) |entry| {
            var actual = index.candidates(&entries, entry.guest_address);
            var expected = rebuilt.candidates(&entries, entry.guest_address);
            while (expected.next()) |wanted| try std.testing.expectEqual(@as(?usize, wanted), actual.next());
            try std.testing.expectEqual(null, actual.next());
        }
    }
    index.insert(entries.len, 0x1000);
    try std.testing.expect(!index.valid);
}
