// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Bounded, per-title SPIR-V catalog for warming the driver's compute cache.
//! Jobs load their own inputs, so queued warmups do not retain shader bodies.
//! Catalogs only affect compilation; their contents are never dispatched.
const std = @import("std");
const compiler = @import("pipeline_compiler.zig");
const allocator = std.heap.page_allocator;
pub const maximum_module_bytes = 16 * 1024 * 1024;
const maximum_catalog_bytes = 512 * 1024 * 1024;
const maximum_save_bytes = 32 * 1024 * 1024;
const maximum_jobs = 2048;

pub const Source = struct {
    context: ?*anyopaque,
    compile: *const fn (?*anyopaque, []const u32) bool,
};

pub const Cache = struct {
    directory: std.Io.Dir,
    jobs: std.ArrayList(*Work) = .empty,
    by_hash: std.AutoHashMapUnmanaged(u64, *Work) = .empty,
    sequence: u64 = 0,
    evictions: u64 = 0,
    evicted_bytes: u64 = 0,
    blocked_saves: u64 = 0,
    source: Source = undefined,
    started: bool = false,
    stopping: std.atomic.Value(bool) = .init(false),
    catalog_bytes: u64 = 0,
    maximum_bytes: u64 = maximum_catalog_bytes,
    maximum_entries: usize = maximum_jobs,
    pending_save_bytes: std.atomic.Value(usize) = .init(0),
    warmed: std.atomic.Value(u32) = .init(0),
    failed: std.atomic.Value(u32) = .init(0),
    cancelled: std.atomic.Value(u32) = .init(0),
    finished: std.atomic.Value(u32) = .init(0),
    warmup_count: u32 = 0,

    pub fn open(path: []const u8) !*Cache {
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        try std.Io.Dir.cwd().createDirPath(io, path);
        const directory = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        errdefer directory.close(io);
        const self = try allocator.create(Cache);
        self.* = .{ .directory = directory };
        return self;
    }

    /// Called on the renderer thread after its address and driver handles are
    /// stable. Enumeration retains only small job records, not SPIR-V bytes.
    pub fn start(self: *Cache, queue: *compiler.Queue, source: Source) void {
        if (self.started) return;
        self.started = true;
        self.source = source;
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        var iterator = self.directory.iterate();
        while (iterator.next(io) catch null) |entry| {
            if (self.jobs.items.len >= self.maximum_entries) break;
            if (entry.kind != .file or entry.name.len != 20 or !std.mem.endsWith(u8, entry.name, ".spv")) continue;
            const hash = std.fmt.parseInt(u64, entry.name[0..16], 16) catch continue;
            if (self.by_hash.contains(hash)) continue;
            const file = self.directory.openFile(io, entry.name, .{}) catch continue;
            const length = file.length(io) catch 0;
            file.close(io);
            if (length < 20 or length > maximum_module_bytes or length % 4 != 0) continue;
            if (self.catalog_bytes + length > self.maximum_bytes) continue;
            const work = allocator.create(Work) catch break;
            work.* = .{ .owner = self, .hash = hash, .byte_count = length };
            self.by_hash.ensureUnusedCapacity(allocator, 1) catch {
                allocator.destroy(work);
                break;
            };
            self.jobs.append(allocator, work) catch {
                allocator.destroy(work);
                break;
            };
            self.by_hash.putAssumeCapacity(hash, work);
            self.catalog_bytes += length;
        }
        self.warmup_count = @intCast(self.jobs.items.len);
        for (self.jobs.items) |work| queue.submitBackground(&work.job);
        if (self.jobs.items.len != 0) std.debug.print(
            "[vulkan compiler] queued {d} compute warmups, workers={d}, catalog={d}MiB\n",
            .{ self.jobs.items.len, queue.worker_limit, self.catalog_bytes / (1024 * 1024) },
        );
    }

    /// Remember successful runtime compilations for the next launch. Workers
    /// own copied words until atomic publication; pending writes are bounded.
    pub fn record(self: *Cache, queue: *compiler.Queue, words: []const u32) void {
        self.recordHashed(queue, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(words)), words);
    }

    /// Renderer-thread cache hits only refresh recency, with no allocation or I/O.
    /// Re-admitting every absent entry here
    /// would churn files each frame when live pipelines exceed the disk budget.
    pub fn touch(self: *Cache, hash: u64) void {
        const work = self.by_hash.get(hash) orelse return;
        self.sequence +|= 1;
        work.last_used_sequence = self.sequence;
    }

    /// The renderer already proves this hash against immutable pipeline words.
    /// Admit only a newly compiled live pipeline, without rescanning its bytes.
    pub fn recordHashed(self: *Cache, queue: *compiler.Queue, hash: u64, words: []const u32) void {
        const bytes = std.mem.sliceAsBytes(words);
        if (!self.started or self.stopping.load(.acquire) or bytes.len < 20 or
            bytes.len > maximum_module_bytes or bytes.len > self.maximum_bytes or
            self.maximum_entries == 0) return;
        self.sequence +|= 1;
        const existing = self.by_hash.get(hash);
        if (existing) |work| {
            work.last_used_sequence = self.sequence;
            // Worker-owned fields are readable only after completion. Failed
            // saves and corrupt inputs may be repaired by current live words.
            if (!work.job.done.isSet() or work.validated) return;
        }
        if (self.pending_save_bytes.load(.acquire) + bytes.len > maximum_save_bytes) {
            self.blocked_saves += 1;
            return;
        }
        // Reserve allocations before deleting any optional cached files.
        const owned = allocator.dupe(u32, words) catch return;
        var accepted = false;
        defer if (!accepted) allocator.free(owned);
        const work = allocator.create(Work) catch return;
        defer if (!accepted) allocator.destroy(work);
        self.jobs.ensureUnusedCapacity(allocator, 1) catch return;
        self.by_hash.ensureUnusedCapacity(allocator, 1) catch return;
        if (!self.makeRoom(bytes.len, existing)) {
            self.blocked_saves += 1;
            return;
        }
        work.* = .{ .owner = self, .hash = hash, .words = owned, .save = true, .byte_count = bytes.len, .last_used_sequence = self.sequence };
        self.jobs.appendAssumeCapacity(work);
        self.by_hash.putAssumeCapacity(hash, work);
        self.catalog_bytes += bytes.len;
        _ = self.pending_save_bytes.fetchAdd(bytes.len, .release);
        accepted = true;
        queue.submitBackground(&work.job);
    }

    fn makeRoom(self: *Cache, bytes: usize, replace: ?*Work) bool {
        if (replace == null and self.catalog_bytes + bytes <= self.maximum_bytes and self.jobs.items.len < self.maximum_entries) return true;
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        if (replace) |old| {
            const index = std.mem.indexOfScalar(*Work, self.jobs.items, old) orelse return false;
            if (!self.removeCompleted(io, index)) return false;
        }
        while (self.catalog_bytes + bytes > self.maximum_bytes or self.jobs.items.len >= self.maximum_entries) {
            var oldest: ?usize = null;
            for (self.jobs.items, 0..) |candidate, index| {
                // Never remove a queued/running reader or a pending publisher.
                if (!candidate.job.done.isSet()) continue;
                if (oldest == null or candidate.last_used_sequence < self.jobs.items[oldest.?].last_used_sequence)
                    oldest = index;
            }
            const index = oldest orelse return false;
            // A locked/unremovable file must still count towards the bound.
            if (!self.removeCompleted(io, index)) return false;
        }
        return true;
    }

    fn removeCompleted(self: *Cache, io: std.Io, index: usize) bool {
        const old = self.jobs.items[index];
        if (!old.job.done.isSet()) return false;
        var name_buffer: [20]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{old.hash}) catch unreachable;
        self.directory.deleteFile(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return false,
        };
        _ = self.by_hash.remove(old.hash);
        _ = self.jobs.swapRemove(index);
        self.catalog_bytes -= old.byte_count;
        self.evictions += 1;
        self.evicted_bytes += old.byte_count;
        allocator.destroy(old);
        return true;
    }

    pub fn stop(self: *Cache) void {
        self.stopping.store(true, .release);
    }

    /// The compiler queue must have been drained/joined first.
    pub fn deinit(self: *Cache) void {
        for (self.jobs.items) |work| allocator.destroy(work);
        self.jobs.deinit(allocator);
        self.by_hash.deinit(allocator);
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        self.directory.close(threaded.io());
        allocator.destroy(self);
    }
};

const Work = struct {
    job: compiler.Job = .{ .run = run },
    owner: *Cache,
    hash: u64,
    byte_count: u64 = 0,
    last_used_sequence: u64 = 0,
    words: ?[]u32 = null,
    save: bool = false,
    validated: bool = false,

    fn run(base: *compiler.Job) void {
        const self: *@This() = @fieldParentPtr("job", base);
        defer if (!self.save) {
            if (self.owner.finished.fetchAdd(1, .acq_rel) + 1 == self.owner.warmup_count) {
                std.debug.print("[vulkan compiler] warmup complete: compiled={d} failed={d} cancelled={d} total={d}\n", .{
                    self.owner.warmed.load(.acquire), self.owner.failed.load(.acquire), self.owner.cancelled.load(.acquire), self.owner.warmup_count,
                });
            }
        };
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        var name_buffer: [20]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{self.hash}) catch unreachable;
        if (self.words) |words| {
            defer {
                _ = self.owner.pending_save_bytes.fetchSub(words.len * 4, .release);
                allocator.free(words);
                self.words = null;
            }
            var nonce: u64 = undefined;
            io.random(std.mem.asBytes(&nonce));
            var temporary_buffer: [48]u8 = undefined;
            const temporary = std.fmt.bufPrint(&temporary_buffer, "{s}.{x}.tmp", .{ name, nonce }) catch unreachable;
            const file = self.owner.directory.createFile(io, temporary, .{ .exclusive = true }) catch return;
            defer self.owner.directory.deleteFile(io, temporary) catch {};
            {
                defer file.close(io);
                file.writePositionalAll(io, std.mem.sliceAsBytes(words), 0) catch return;
            }
            self.owner.directory.rename(temporary, self.owner.directory, name, io) catch return;
            self.validated = true;
            return;
        }
        if (self.owner.stopping.load(.acquire)) {
            _ = self.owner.cancelled.fetchAdd(1, .monotonic);
            return;
        }
        const bytes = self.owner.directory.readFileAllocOptions(io, name, allocator, .limited(maximum_module_bytes), .of(u32), null) catch return;
        defer allocator.free(bytes);
        if (!validModule(bytes, self.hash)) {
            _ = self.owner.failed.fetchAdd(1, .monotonic);
            return;
        }
        self.validated = true;
        if (self.owner.source.compile(self.owner.source.context, std.mem.bytesAsSlice(u32, bytes))) {
            _ = self.owner.warmed.fetchAdd(1, .monotonic);
        } else {
            _ = self.owner.failed.fetchAdd(1, .monotonic);
        }
    }
};

fn validModule(bytes: []const u8, hash: u64) bool {
    if (bytes.len < 20 or bytes.len % 4 != 0 or std.hash.Wyhash.hash(0, bytes) != hash) return false;
    if (std.mem.readInt(u32, bytes[0..4], .little) != 0x07230203) return false;
    var offset: usize = 20;
    while (offset < bytes.len) {
        const count = std.mem.readInt(u32, bytes[offset..][0..4], .little) >> 16;
        if (count == 0 or count > (bytes.len - offset) / 4) return false;
        offset += count * 4;
    }
    return true;
}

test "warmup validates complete module bytes and rejects corruption" {
    const words = [_]u32{ 0x07230203, 0x00010500, 0, 1, 0, 0x00010000 };
    const bytes = std.mem.sliceAsBytes(&words);
    const hash = std.hash.Wyhash.hash(0, bytes);
    try std.testing.expect(validModule(bytes, hash));
    try std.testing.expect(!validModule(bytes[0 .. bytes.len - 1], hash));
    var corrupt = words;
    corrupt[5] = 0;
    const corrupt_bytes = std.mem.sliceAsBytes(&corrupt);
    try std.testing.expect(!validModule(corrupt_bytes, std.hash.Wyhash.hash(0, corrupt_bytes)));
    try std.testing.expect(!validModule(bytes, hash +% 1));
}

test "catalog saves once then warms validated words and repairs corruption" {
    const Probe = struct {
        calls: std.atomic.Value(u32) = .init(0),
        fn compile(raw: ?*anyopaque, words: []const u32) bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (words.len != 6 or words[5] != 0x00010000) return false;
            _ = self.calls.fetchAdd(1, .monotonic);
            return true;
        }
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var queue = compiler.Queue{};
    defer queue.deinit();
    const cache = try allocator.create(Cache);
    cache.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }) };
    defer {
        queue.waitIdle();
        cache.deinit();
    }
    var probe = Probe{};
    const source = Source{ .context = &probe, .compile = Probe.compile };
    cache.start(&queue, source);
    const words = [_]u32{ 0x07230203, 0x00010500, 0, 1, 0, 0x00010000 };
    cache.record(&queue, &words);
    cache.record(&queue, &words);
    queue.waitIdle();
    try std.testing.expectEqual(@as(usize, 1), cache.jobs.items.len);
    try std.testing.expectEqual(@as(usize, 0), cache.pending_save_bytes.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), probe.calls.load(.acquire));

    const replay = try allocator.create(Cache);
    replay.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }) };
    defer {
        queue.waitIdle();
        replay.deinit();
    }
    replay.start(&queue, source);
    queue.waitIdle();
    try std.testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), replay.warmed.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), replay.failed.load(.acquire));

    var name_buffer: [20]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&words))});
    var corrupt = words;
    corrupt[5] = 0;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = std.mem.sliceAsBytes(&corrupt) });
    const repair = try allocator.create(Cache);
    repair.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }) };
    defer {
        queue.waitIdle();
        repair.deinit();
    }
    repair.start(&queue, source);
    queue.waitIdle();
    try std.testing.expectEqual(@as(u32, 1), repair.failed.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    repair.record(&queue, &words);
    queue.waitIdle();
    const restored = try temporary.dir.readFileAlloc(std.testing.io, name, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(restored);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&words), restored);
}

test "catalog bounds pending saves and cancels unstarted warmups at shutdown" {
    const Probe = struct {
        fn compile(_: ?*anyopaque, _: []const u32) bool {
            @panic("stopped warmup must not compile");
        }
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try allocator.create(Cache);
    cache.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }) };
    defer cache.deinit();
    var queue = compiler.Queue{};
    defer queue.deinit();
    cache.start(&queue, .{ .context = null, .compile = Probe.compile });
    const words = [_]u32{ 0x07230203, 0x00010500, 0, 1, 0, 0x00010000 };
    cache.pending_save_bytes.store(maximum_save_bytes, .release);
    cache.record(&queue, &words);
    try std.testing.expectEqual(@as(usize, 0), cache.jobs.items.len);
    cache.pending_save_bytes.store(0, .release);
    cache.record(&queue, &words);
    queue.waitIdle();
    const replay = try allocator.create(Cache);
    replay.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }) };
    defer {
        queue.waitIdle();
        replay.deinit();
    }
    replay.stop();
    replay.start(&queue, .{ .context = null, .compile = Probe.compile });
    queue.waitIdle();
    try std.testing.expectEqual(@as(usize, 1), replay.jobs.items.len);
    try std.testing.expectEqual(@as(u32, 0), replay.warmed.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), replay.cancelled.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), replay.finished.load(.acquire));
}

test "catalog replaces cold completed modules at both bounds and replays recent modules" {
    const Probe = struct {
        seen: std.atomic.Value(u32) = .init(0),
        fn compile(raw: ?*anyopaque, words: []const u32) bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = self.seen.fetchOr(@as(u32, 1) << @intCast(words[2]), .monotonic);
            return true;
        }
    };
    for ([_]struct { bytes: u64, entries: usize }{ .{ .bytes = 48, .entries = 8 }, .{ .bytes = 192, .entries = 2 } }) |limits| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var queue = compiler.Queue{};
        defer queue.deinit();
        const cache = try allocator.create(Cache);
        cache.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }), .maximum_bytes = limits.bytes, .maximum_entries = limits.entries };
        defer {
            queue.waitIdle();
            cache.deinit();
        }
        var probe = Probe{};
        const source = Source{ .context = &probe, .compile = Probe.compile };
        cache.start(&queue, source);
        const a = [_]u32{ 0x07230203, 0x00010500, 1, 1, 0, 0x00010000 };
        const b = [_]u32{ 0x07230203, 0x00010500, 2, 1, 0, 0x00010000 };
        const newer = [_]u32{ 0x07230203, 0x00010500, 3, 1, 0, 0x00010000 };
        cache.touch(std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&newer)));
        try std.testing.expectEqual(@as(usize, 0), cache.jobs.items.len);
        cache.record(&queue, &a);
        cache.record(&queue, &b);
        queue.waitIdle();
        // A is still being used when C arrives; B must be the victim.
        cache.touch(std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&a)));
        cache.record(&queue, &newer);
        queue.waitIdle();
        var name_buffer: [20]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&newer))});
        const saved = try temporary.dir.readFileAlloc(std.testing.io, name, std.testing.allocator, .limited(64));
        defer std.testing.allocator.free(saved);
        try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&newer), saved);
        try std.testing.expectEqual(@as(usize, 2), cache.jobs.items.len);
        try std.testing.expectEqual(@as(u64, 48), cache.catalog_bytes);
        const replay = try allocator.create(Cache);
        replay.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }), .maximum_bytes = limits.bytes, .maximum_entries = limits.entries };
        defer {
            queue.waitIdle();
            replay.deinit();
        }
        replay.start(&queue, source);
        queue.waitIdle();
        try std.testing.expectEqual(@as(u32, (1 << 1) | (1 << 3)), probe.seen.load(.acquire));
        try std.testing.expectEqual(@as(u32, 2), replay.warmed.load(.acquire));
    }
}

test "catalog never evicts an active warmup and retries once it completes" {
    const Probe = struct {
        entered: std.atomic.Value(bool) = .init(false),
        gate: std.Io.Event = .unset,
        fn compile(raw: ?*anyopaque, _: []const u32) bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.store(true, .release);
            self.gate.waitUncancelable(std.Io.Threaded.global_single_threaded.io());
            return true;
        }
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var queue = compiler.Queue{ .worker_limit = 1 };
    defer queue.deinit();
    const a = [_]u32{ 0x07230203, 0x00010500, 1, 1, 0, 0x00010000 };
    const b = [_]u32{ 0x07230203, 0x00010500, 2, 1, 0, 0x00010000 };
    var name_buffer: [20]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&a))});
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = std.mem.sliceAsBytes(&a) });
    const cache = try allocator.create(Cache);
    cache.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }), .maximum_bytes = 24, .maximum_entries = 1 };
    var probe = Probe{};
    defer {
        probe.gate.set(std.Io.Threaded.global_single_threaded.io());
        queue.waitIdle();
        cache.deinit();
    }
    cache.start(&queue, .{ .context = &probe, .compile = Probe.compile });
    const start = std.Io.Clock.awake.now(std.testing.io).nanoseconds;
    while (!probe.entered.load(.acquire)) {
        if (std.Io.Clock.awake.now(std.testing.io).nanoseconds - start > 5 * std.time.ns_per_s) return error.WorkerDidNotStart;
        std.Thread.yield() catch {};
    }
    cache.record(&queue, &b);
    try std.testing.expectEqual(@as(u64, 0), cache.evictions);
    try std.testing.expectEqual(@as(u64, 1), cache.blocked_saves);
    try std.testing.expectEqual(@as(u64, 24), cache.catalog_bytes);
    try std.testing.expectEqual(@as(usize, 0), cache.pending_save_bytes.load(.acquire));
    const intact = try temporary.dir.readFileAlloc(std.testing.io, name, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(intact);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&a), intact);
    probe.gate.set(std.Io.Threaded.global_single_threaded.io());
    queue.waitIdle();
    cache.record(&queue, &b);
    queue.waitIdle();
    try std.testing.expectEqual(@as(u64, 1), cache.evictions);
    try std.testing.expectError(error.FileNotFound, temporary.dir.openFile(std.testing.io, name, .{}));
    const saved_name = try std.fmt.bufPrint(&name_buffer, "{x:0>16}.spv", .{std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&b))});
    const saved = try temporary.dir.readFileAlloc(std.testing.io, saved_name, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(saved);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&b), saved);
}

test "catalog larger replacement evicts multiple files without exceeding its byte bound" {
    const Probe = struct {
        fn compile(_: ?*anyopaque, _: []const u32) bool {
            return true;
        }
    };
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var queue = compiler.Queue{};
    defer queue.deinit();
    const cache = try allocator.create(Cache);
    cache.* = .{ .directory = try temporary.dir.openDir(std.testing.io, ".", .{ .iterate = true }), .maximum_bytes = 48, .maximum_entries = 8 };
    defer {
        queue.waitIdle();
        cache.deinit();
    }
    cache.start(&queue, .{ .context = null, .compile = Probe.compile });
    const a = [_]u32{ 0x07230203, 0x00010500, 1, 1, 0, 0x00010000 };
    const b = [_]u32{ 0x07230203, 0x00010500, 2, 1, 0, 0x00010000 };
    const large = [_]u32{ 0x07230203, 0x00010500, 3, 1, 0, 0x00010000, 0x00010000, 0x00010000, 0x00010000, 0x00010000, 0x00010000, 0x00010000 };
    cache.record(&queue, &a);
    cache.record(&queue, &b);
    queue.waitIdle();
    cache.record(&queue, &large);
    queue.waitIdle();
    try std.testing.expectEqual(@as(u64, 2), cache.evictions);
    try std.testing.expectEqual(@as(u64, 48), cache.catalog_bytes);
    try std.testing.expectEqual(@as(usize, 1), cache.jobs.items.len);
    var iterator = temporary.dir.iterate();
    var files: usize = 0;
    var bytes: u64 = 0;
    while (try iterator.next(std.testing.io)) |entry| {
        const file = try temporary.dir.openFile(std.testing.io, entry.name, .{});
        defer file.close(std.testing.io);
        bytes += try file.length(std.testing.io);
        files += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), files);
    try std.testing.expectEqual(@as(u64, 48), bytes);
    cache.stop();
    cache.record(&queue, &a);
    try std.testing.expectEqual(@as(usize, 1), cache.jobs.items.len);
}
