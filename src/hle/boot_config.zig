// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Launch preferences applied to the Unity boot document exposed by /app0.
//! The installed document is never modified.
const std = @import("std");

pub const path = "Media/boot.config";
pub const maximum_bytes = 64 * 1024;

pub fn rewrite(source: []const u8, output: []u8, width: u32, height: u32) error{NoSpaceLeft}!?[]const u8 {
    var used: usize = 0;
    var changed = false;
    var cursor: usize = 0;
    while (cursor < source.len) {
        const line_end = if (std.mem.indexOfScalarPos(u8, source, cursor, '\n')) |end| end + 1 else source.len;
        const line = source[cursor..line_end];
        const body = std.mem.trimEnd(u8, line, "\r\n");
        const value: ?u32 = if (std.mem.startsWith(u8, body, "platform-ps5-video-out-width=") or
            std.mem.startsWith(u8, body, "platform-ps5-standardmode-video-out-width=")) width else if (std.mem.startsWith(u8, body, "platform-ps5-video-out-height=") or
            std.mem.startsWith(u8, body, "platform-ps5-standardmode-video-out-height=")) height else null;
        if (value) |dimension| {
            const equal = std.mem.indexOfScalar(u8, body, '=').?;
            const replacement = std.fmt.bufPrint(output[used..], "{s}{d}{s}", .{ body[0 .. equal + 1], dimension, line[body.len..] }) catch return error.NoSpaceLeft;
            used += replacement.len;
            changed = true;
        } else {
            if (line.len > output.len - used) return error.NoSpaceLeft;
            @memcpy(output[used..][0..line.len], line);
            used += line.len;
        }
        cursor = line_end;
    }
    return if (changed) output[0..used] else null;
}

test "Unity display overrides preserve unrelated settings and line endings" {
    var output: [256]u8 = undefined;
    const source = "gfx-enable-gfx-jobs=1\r\nplatform-ps5-video-out-width=3840\r\nplatform-ps5-video-out-height=2160\nkeep=123";
    const result = (try rewrite(source, &output, 1920, 1080)).?;
    try std.testing.expectEqualStrings("gfx-enable-gfx-jobs=1\r\nplatform-ps5-video-out-width=1920\r\nplatform-ps5-video-out-height=1080\nkeep=123", result);
    try std.testing.expect((try rewrite("unrelated=3840\n", &output, 1920, 1080)) == null);
    try std.testing.expectError(error.NoSpaceLeft, rewrite(source, output[0..5], 1920, 1080));
    try std.testing.expectEqualStrings("platform-ps5-video-out-width=7680", (try rewrite("platform-ps5-video-out-width=1920", &output, 7680, 4320)).?);
    try std.testing.expectEqualStrings("platform-ps5-standardmode-video-out-width=1920\nplatform-ps5-video-out-120hz=1\n", (try rewrite("platform-ps5-standardmode-video-out-width=3840\nplatform-ps5-video-out-120hz=1\n", &output, 1920, 1080)).?);
}
