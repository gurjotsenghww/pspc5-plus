// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! A range occupies one aligned power-of-two region. Short writes query the
//! occupied region levels; collisions still require the caller's exact check.
const std = @import("std");

pub fn Index(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Slot = if (capacity < std.math.maxInt(u16)) u16 else u32;
        const empty = std.math.maxInt(Slot);
        const bucket_count = std.math.ceilPowerOfTwoAssert(usize, @max(16, capacity * 2));
        heads: [bucket_count]Slot = undefined,
        links: [capacity]Slot = undefined,
        level_heads: [65]Slot = undefined,
        level_next: [capacity]Slot = undefined,
        level_previous: [capacity]Slot = undefined,
        level_counts: [65]usize = undefined,
        levels: u128 = 0,
        valid: bool = false,

        pub const Iterator = struct {
            remaining: std.StaticBitSet(capacity) = .initEmpty(),
            linear_next: usize = 0,
            linear_end: usize = 0,

            pub fn next(self: *Iterator) ?usize {
                if (self.linear_next < self.linear_end) {
                    defer self.linear_next += 1;
                    return self.linear_next;
                }
                const slot = self.remaining.findFirstSet() orelse return null;
                self.remaining.unset(slot);
                return slot;
            }
        };

        fn level(address: u64, size: u64) u7 {
            const last = address +| (size -| 1);
            return @intCast(64 - @clz(address ^ last));
        }

        fn region(address: u64, height: u7) u64 {
            return if (height == 64) 0 else address >> @as(u6, @intCast(height));
        }

        fn bucket(key: u64, height: u7) usize {
            var hash = key ^ (@as(u64, height) *% 0x9e3779b97f4a7c15);
            hash ^= hash >> 33;
            hash *%= 0xff51afd7ed558ccd;
            hash ^= hash >> 33;
            return @intCast(hash & (bucket_count - 1));
        }

        pub fn invalidate(self: *Self) void {
            self.valid = false;
        }

        pub fn insert(self: *Self, slot: usize, address: u64, size: u64) void {
            if (!self.valid) return;
            if (slot >= capacity) return self.invalidate();
            const height = level(address, size);
            const head = &self.heads[bucket(region(address, height), height)];
            self.links[slot] = head.*;
            head.* = @intCast(slot);
            self.linkLevel(slot, height);
        }

        fn linkLevel(self: *Self, slot: usize, height: u7) void {
            const next = self.level_heads[height];
            self.level_next[slot] = next;
            self.level_previous[slot] = empty;
            if (next != empty) self.level_previous[next] = @intCast(slot);
            self.level_heads[height] = @intCast(slot);
            self.level_counts[height] += 1;
            self.levels |= @as(u128, 1) << height;
        }

        fn unlinkLevel(self: *Self, slot: usize, height: u7) void {
            const previous = self.level_previous[slot];
            const next = self.level_next[slot];
            if (previous == empty) self.level_heads[height] = next else self.level_next[previous] = next;
            if (next != empty) self.level_previous[next] = previous;
            self.level_counts[height] -= 1;
            if (self.level_counts[height] == 0) self.levels &= ~(@as(u128, 1) << height);
        }

        pub fn replace(self: *Self, slot: usize, old_address: u64, old_size: u64, address: u64, size: u64) void {
            if (!self.valid) return;
            if (slot >= capacity) return self.invalidate();
            const old_height = level(old_address, old_size);
            const old_bucket = bucket(region(old_address, old_height), old_height);
            const new_height = level(address, size);
            const new_bucket = bucket(region(address, new_height), new_height);
            if (old_height != new_height) {
                self.unlinkLevel(slot, old_height);
                self.linkLevel(slot, new_height);
            }
            if (old_bucket == new_bucket) return;
            var link = &self.heads[old_bucket];
            while (link.* != empty and link.* != slot) link = &self.links[link.*];
            if (link.* == empty) return self.invalidate();
            link.* = self.links[slot];
            self.links[slot] = self.heads[new_bucket];
            self.heads[new_bucket] = @intCast(slot);
        }

        pub fn candidates(self: *Self, items: anytype, address: u64, size: usize) Iterator {
            if (size == 0) return .{};
            if (items.len > capacity) return .{ .linear_end = items.len };
            if (!self.valid) {
                @memset(&self.heads, empty);
                @memset(&self.level_heads, empty);
                @memset(&self.level_counts, 0);
                self.levels = 0;
                self.valid = true;
                for (items, 0..) |item, slot| self.insert(slot, item.guest_address, item.size);
            }
            // A sparse level of tiny ranges must not force a scan of every
            // allocation. Choose bucket lookup or its own list independently.
            var result = Iterator{};
            var levels = self.levels;
            while (levels != 0) {
                const height: u7 = @intCast(@ctz(levels));
                levels &= levels - 1;
                var key = region(address, height);
                const last = region(address +| (size - 1), height);
                const count = (last - key) +| 1;
                if (count > @min(256, self.level_counts[height])) {
                    var slot = self.level_heads[height];
                    while (slot != empty) {
                        const entry_key = region(items[slot].guest_address, height);
                        if (entry_key >= key and entry_key <= last) result.remaining.set(slot);
                        slot = self.level_next[slot];
                    }
                    continue;
                }
                while (true) {
                    var slot = self.heads[bucket(key, height)];
                    while (slot != empty) {
                        result.remaining.set(slot);
                        slot = self.links[slot];
                    }
                    if (key == last) break;
                    key += 1;
                }
            }
            // A bit set deduplicates hash collisions and preserves cache order.
            return result;
        }
    };
}

test "overlap index preserves nested ranges, boundaries, replacement and removal" {
    const Entry = struct { guest_address: u64, size: u64 };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(std.testing.allocator);
    var index = Index(128){};
    for (0..96) |i| try entries.append(std.testing.allocator, .{ .guest_address = 0x1000 + i * 19, .size = 1 + (i * 71) % 1200 });
    for (0..3) |round| {
        for (0..240) |i| {
            const address: u64 = 0xff0 + i * 11;
            const size: usize = 1 + i % 90;
            var actual = std.StaticBitSet(128).initEmpty();
            var candidates = index.candidates(entries.items, address, size);
            var previous: ?usize = null;
            while (candidates.next()) |slot| {
                if (previous) |p| try std.testing.expect(slot > p);
                previous = slot;
                const e = entries.items[slot];
                if (address < e.guest_address + e.size and e.guest_address < address + size) actual.set(slot);
            }
            for (entries.items, 0..) |e, slot| try std.testing.expectEqual(address < e.guest_address + e.size and e.guest_address < address + size, actual.isSet(slot));
        }
        if (round == 0) {
            for (entries.items, 0..) |*e, slot| {
                const next = Entry{ .guest_address = 0x1080 + slot * 7, .size = 1 + slot % 33 };
                index.replace(slot, e.guest_address, e.size, next.guest_address, next.size);
                e.* = next;
            }
        } else if (round == 1) {
            _ = entries.swapRemove(17);
            index.invalidate();
        }
    }
}

test "overlap index handles high address bits, append and oversized caches" {
    const Entry = struct { guest_address: u64, size: u64 };
    var index = Index(2){};
    var entries = [_]Entry{
        .{ .guest_address = 0x7ffffffffffffff0, .size = 32 },
        .{ .guest_address = 0xfffffffffffffff8, .size = 8 },
        .{ .guest_address = 0x1000, .size = 4 },
    };
    var a = index.candidates(entries[0..1], 0x8000000000000000, 4);
    try std.testing.expectEqual(@as(?usize, 0), a.next());
    index.insert(1, entries[1].guest_address, entries[1].size);
    var b = index.candidates(entries[0..2], 0xffffffffffffffff, 1);
    var found = false;
    while (b.next()) |slot| if (slot == 1) {
        found = true;
    };
    try std.testing.expect(found);
    var c = index.candidates(&entries, 0x1000, 4);
    for (0..3) |slot| try std.testing.expectEqual(@as(?usize, slot), c.next());
    try std.testing.expectEqual(null, c.next());
    var empty = index.candidates(&entries, 0x1000, 0);
    try std.testing.expectEqual(null, empty.next());
}

test "short writes avoid scanning a full resident cache" {
    const Entry = struct { guest_address: u64, size: u64 };
    var entries: [4096]Entry = undefined;
    for (&entries, 0..) |*e, i| e.* = .{ .guest_address = 0x100000 + i * 4096, .size = 128 };
    entries[4000] = .{ .guest_address = 0x100000, .size = 8 * 1024 * 1024 };
    var index = Index(4096){};
    var candidates = index.candidates(&entries, entries[1200].guest_address + 56, 4);
    var checked: usize = 0;
    var narrow = false;
    var wide = false;
    while (candidates.next()) |slot| {
        checked += 1;
        narrow = narrow or slot == 1200;
        wide = wide or slot == 4000;
    }
    try std.testing.expect(narrow and wide);
    try std.testing.expect(checked < 64);
}

test "buffer-sized overlap queries avoid scanning unrelated allocations" {
    const Entry = struct { guest_address: u64, size: u64 };
    var entries: [4096]Entry = undefined;
    for (&entries, 0..) |*entry, i| entry.* = .{ .guest_address = 0x100000 + i * 4096, .size = 128 };
    entries[4000] = .{ .guest_address = 0x100000, .size = 8 * 1024 * 1024 };
    var index = Index(4096){};
    for ([_]usize{ 128, 512, 4096 }) |size| {
        var candidates = index.candidates(&entries, entries[1200].guest_address, size);
        var checked: usize = 0;
        var narrow = false;
        var wide = false;
        while (candidates.next()) |slot| {
            checked += 1;
            narrow = narrow or slot == 1200;
            wide = wide or slot == 4000;
        }
        try std.testing.expect(narrow and wide);
        try std.testing.expect(checked < 64);
    }
}

test "a sparse tiny range does not force whole-cache overlap scans" {
    const Entry = struct { guest_address: u64, size: u64 };
    var entries: [4096]Entry = undefined;
    for (&entries, 0..) |*entry, i| entry.* = .{ .guest_address = 0x100000 + i * 4096, .size = 128 };
    entries[4095].size = 1;
    var index = Index(4096){};
    for (0..4) |round| {
        var candidates = index.candidates(&entries, entries[1200].guest_address, 4096);
        var checked: usize = 0;
        var found = false;
        while (candidates.next()) |slot| {
            checked += 1;
            found = found or slot == 1200;
        }
        try std.testing.expect(found);
        try std.testing.expect(checked < 64);
        const next_size: u64 = if (round % 2 == 0) 32 else 1;
        index.replace(4095, entries[4095].guest_address, entries[4095].size, entries[4095].guest_address, next_size);
        entries[4095].size = next_size;
    }
}
