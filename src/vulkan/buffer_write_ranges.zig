// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Bounded, conservative byte coverage of pending GPU writes. An unknown
//! address or exhausted span budget restores whole-buffer publication.
const std = @import("std");

pub const Span = struct { first: usize, end: usize };
pub const capacity = 8;

pub const Ranges = struct {
    whole: bool = false,
    count: usize = 0,
    spans: [capacity]Span = undefined,

    pub fn include(self: *Ranges, span: Span) void {
        if (self.whole or span.first >= span.end) return;
        var merged = span;
        var first: usize = 0;
        while (first < self.count and self.spans[first].end < merged.first) : (first += 1) {}
        var last = first;
        while (last < self.count and self.spans[last].first <= merged.end) : (last += 1) {
            merged.first = @min(merged.first, self.spans[last].first);
            merged.end = @max(merged.end, self.spans[last].end);
        }
        const remaining = self.count - (last - first);
        if (remaining == capacity) {
            self.* = .{ .whole = true };
            return;
        }
        if (last > first)
            std.mem.copyForwards(Span, self.spans[first + 1 .. remaining + 1], self.spans[last..self.count])
        else
            std.mem.copyBackwards(Span, self.spans[first + 1 .. remaining + 1], self.spans[last..self.count]);
        self.spans[first] = merged;
        self.count = remaining + 1;
    }

    pub fn merge(self: *Ranges, other: *const Ranges) void {
        if (other.whole) {
            self.* = .{ .whole = true };
            return;
        }
        for (other.spans[0..other.count]) |span| self.include(span);
    }

    pub fn prefix(self: *const Ranges, size: usize, output: *[capacity]Span) []const Span {
        if (size == 0) return output[0..0];
        if (self.whole) {
            output[0] = .{ .first = 0, .end = size };
            return output[0..1];
        }
        var count: usize = 0;
        for (self.spans[0..self.count]) |span| {
            if (span.first >= size) break;
            output[count] = .{ .first = span.first, .end = @min(span.end, size) };
            count += 1;
        }
        return output[0..count];
    }
};

test "write spans merge overlap and adjacency without publishing the gaps" {
    var ranges = Ranges{};
    ranges.include(.{ .first = 32, .end = 36 });
    ranges.include(.{ .first = 0, .end = 4 });
    ranges.include(.{ .first = 60, .end = 64 });
    ranges.include(.{ .first = 4, .end = 8 });
    ranges.include(.{ .first = 6, .end = 34 });
    try std.testing.expectEqual(@as(usize, 2), ranges.count);
    try std.testing.expectEqual(Span{ .first = 0, .end = 36 }, ranges.spans[0]);
    try std.testing.expectEqual(Span{ .first = 60, .end = 64 }, ranges.spans[1]);
    var clipped: [capacity]Span = undefined;
    const prefix = ranges.prefix(62, &clipped);
    try std.testing.expectEqual(Span{ .first = 60, .end = 62 }, prefix[1]);
    try std.testing.expectEqual(@as(usize, 0), ranges.prefix(0, &clipped).len);
}

test "write span overflow and unknown writes retain every GPU result" {
    var ranges = Ranges{};
    for (0..capacity + 1) |i| ranges.include(.{ .first = i * 8, .end = i * 8 + 4 });
    try std.testing.expect(ranges.whole);
    var clipped: [capacity]Span = undefined;
    try std.testing.expectEqual(Span{ .first = 0, .end = 128 }, ranges.prefix(128, &clipped)[0]);
    var known = Ranges{};
    known.include(.{ .first = 32, .end = 36 });
    known.merge(&ranges);
    try std.testing.expect(known.whole);
    known.include(.{ .first = 0, .end = 4 });
    try std.testing.expect(known.whole);
}
