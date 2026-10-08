// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Allocation-free recency order for a dense cache whose removals swap in
//! its last slot. Every live slot appears once, from oldest to newest.
const std = @import("std");

pub fn Index(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Slot = if (capacity <= std.math.maxInt(u16)) u16 else u32;
        const empty = std.math.maxInt(Slot);
        const Node = struct { previous: Slot = empty, next: Slot = empty };

        nodes: [capacity]Node = undefined,
        head: Slot = empty,
        tail: Slot = empty,
        len: usize = 0,

        /// Append the slot at the end of the dense cache.
        pub fn append(self: *Self) void {
            std.debug.assert(self.len < capacity);
            self.linkNewest(@intCast(self.len));
            self.len += 1;
        }

        pub fn touch(self: *Self, index: usize) void {
            std.debug.assert(index < self.len);
            const slot: Slot = @intCast(index);
            if (slot == self.tail) return;
            self.unlink(slot);
            self.linkNewest(slot);
        }

        /// Mirror ArrayList.swapRemove: discard index, then move the last
        /// live slot into its place without changing the moved slot's age.
        pub fn removeSwap(self: *Self, index: usize) void {
            std.debug.assert(index < self.len);
            const slot: Slot = @intCast(index);
            const last: Slot = @intCast(self.len - 1);
            self.unlink(slot);
            self.len -= 1;
            if (slot == last) return;
            const moved = self.nodes[last];
            self.nodes[slot] = moved;
            if (moved.previous == empty) self.head = slot else self.nodes[moved.previous].next = slot;
            if (moved.next == empty) self.tail = slot else self.nodes[moved.next].previous = slot;
        }

        fn unlink(self: *Self, slot: Slot) void {
            const node = self.nodes[slot];
            if (node.previous == empty) self.head = node.next else self.nodes[node.previous].next = node.next;
            if (node.next == empty) self.tail = node.previous else self.nodes[node.next].previous = node.previous;
        }

        fn linkNewest(self: *Self, slot: Slot) void {
            self.nodes[slot] = .{ .previous = self.tail };
            if (self.tail == empty) self.head = slot else self.nodes[self.tail].next = slot;
            self.tail = slot;
        }

        pub const Iterator = struct {
            order: *const Self,
            slot: Slot,

            pub fn next(self: *Iterator) ?usize {
                if (self.slot == empty) return null;
                const slot = self.slot;
                self.slot = self.order.nodes[slot].next;
                return slot;
            }
        };

        /// Mutating the cache invalidates this iterator.
        pub fn oldestFirst(self: *const Self) Iterator {
            return .{ .order = self, .slot = self.head };
        }
    };
}

test "recency survives all removal and moved-slot adjacency combinations" {
    for (0..5) |hot| for (0..5) |removed| {
        var order = Index(5){};
        for (0..5) |_| order.append();
        order.touch(hot);
        order.removeSwap(removed);
        var expected: [4]usize = undefined;
        var count: usize = 0;
        for (0..6) |position| {
            const slot = if (position == 5) hot else position;
            if (position != 5 and slot == hot) continue;
            if (slot == removed) continue;
            expected[count] = if (slot == 4) removed else slot;
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 4), count);
        var it = order.oldestFirst();
        for (expected) |slot| try std.testing.expectEqual(@as(?usize, slot), it.next());
        try std.testing.expectEqual(null, it.next());
        // A subsequent append reuses the vacated last physical slot.
        order.append();
        order.touch(4);
        it = order.oldestFirst();
        for (expected) |slot| try std.testing.expectEqual(@as(?usize, slot), it.next());
        try std.testing.expectEqual(@as(?usize, 4), it.next());
        try std.testing.expectEqual(null, it.next());
    };
}

test "recency matches an independent ordered-list model through slot recycling" {
    var order = Index(64){};
    var reference: [64]usize = undefined;
    var len: usize = 0;
    var seed: u64 = 0x713fe66201;
    for (0..10000) |_| {
        seed = seed *% 6364136223846793005 +% 1;
        const operation = (seed >> 32) % 3;
        if (len == 0 or (operation == 0 and len < reference.len)) {
            order.append();
            reference[len] = len;
            len += 1;
        } else {
            const slot: usize = @intCast(seed % len);
            const position = std.mem.indexOfScalar(usize, reference[0..len], slot).?;
            std.mem.copyForwards(usize, reference[position .. len - 1], reference[position + 1 .. len]);
            if (operation == 2) {
                order.removeSwap(slot);
                len -= 1;
                for (reference[0..len]) |*value| if (value.* == len) {
                    value.* = slot;
                };
            } else {
                order.touch(slot);
                reference[len - 1] = slot;
            }
        }
        try std.testing.expectEqual(len, order.len);
        var it = order.oldestFirst();
        for (reference[0..len]) |slot| try std.testing.expectEqual(@as(?usize, slot), it.next());
        try std.testing.expectEqual(null, it.next());
    }
}
