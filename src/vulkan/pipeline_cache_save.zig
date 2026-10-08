// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! One outstanding driver-cache snapshot. The renderer joins before destroying
//! the cache/device; no driver handles or renderer allocator reach a detached job.
const std = @import("std");
const builtin = @import("builtin");
const vk = @import("api.zig");

pub const Header = struct {
    header_size: u32,
    header_version: u32,
    vendor_id: u32,
    device_id: u32,
    pipeline_cache_uuid: [16]u8,

    pub const current_version: u32 = 1;
    pub const header_size_bytes: usize = 32;

    pub fn read(bytes: []const u8) ?Header {
        if (bytes.len < header_size_bytes) return null;
        var uuid: [16]u8 = undefined;
        @memcpy(&uuid, bytes[16..32]);
        return .{
            .header_size = std.mem.readInt(u32, bytes[0..4], .little),
            .header_version = std.mem.readInt(u32, bytes[4..8], .little),
            .vendor_id = std.mem.readInt(u32, bytes[8..12], .little),
            .device_id = std.mem.readInt(u32, bytes[12..16], .little),
            .pipeline_cache_uuid = uuid,
        };
    }

    pub fn validate(
        bytes: []const u8,
        expected_vendor_id: u32,
        expected_device_id: u32,
        expected_uuid: *const [16]u8,
    ) bool {
        const header = read(bytes) orelse return false;
        if (header.header_size < header_size_bytes) return false;
        if (header.header_version != current_version) return false;
        if (header.vendor_id != expected_vendor_id) return false;
        if (header.device_id != expected_device_id) return false;
        if (!std.mem.eql(u8, &header.pipeline_cache_uuid, expected_uuid)) return false;
        return true;
    }

    pub fn write(self: Header, destination: []u8) !void {
        if (destination.len < header_size_bytes) return error.BufferTooSmall;
        std.mem.writeInt(u32, destination[0..4], self.header_size, .little);
        std.mem.writeInt(u32, destination[4..8], self.header_version, .little);
        std.mem.writeInt(u32, destination[8..12], self.vendor_id, .little);
        std.mem.writeInt(u32, destination[12..16], self.device_id, .little);
        @memcpy(destination[16..32], &self.pipeline_cache_uuid);
    }
};

pub const Source = struct {
    device: vk.Device,
    cache: vk.PipelineCache,
    get_data: vk.PfnGetPipelineCacheData,
    generation: u64,
    maximum_bytes: usize,
    /// Large Windows snapshots use a data-file mapping instead of reserving
    /// another cache-sized block of system commit beside the driver's cache.
    mapped_file_threshold: usize = 16 * 1024 * 1024,
    directory: std.Io.Dir,
    path: []const u8,
};

pub const Saver = struct {
    job: ?*Job = null,
    persisted_generation: u64 = 0,
    last_checkpoint_ns: ?u64 = null,
    last_failure: ?anyerror = null,

    /// Loading can spend minutes compiling pipelines without presenting a
    /// frame. Check after each compilation as well as on flips, and bound
    /// snapshot frequency independently of the game's frame rate.
    pub fn checkpoint(self: *Saver, source: Source, now_ns: u64) bool {
        const interval_ns = 30 * std.time.ns_per_s;
        if (self.last_checkpoint_ns) |last| {
            if (now_ns -| last < interval_ns) return false;
        }
        if (!self.request(source)) return false;
        self.last_checkpoint_ns = now_ns;
        return true;
    }

    /// A busy writer coalesces requests. A newer generation is retried after
    /// this snapshot completes, without claiming it was included in the file.
    pub fn request(self: *Saver, source: Source) bool {
        self.reap(false);
        if (self.job != null or source.generation == self.persisted_generation) return false;
        const job = std.heap.page_allocator.create(Job) catch return false;
        job.* = .{ .source = source };
        job.thread = std.Thread.spawn(.{}, Job.run, .{job}) catch {
            std.heap.page_allocator.destroy(job);
            return false;
        };
        self.job = job;
        return true;
    }

    pub fn join(self: *Saver) void {
        self.reap(true);
    }

    /// Called only after pipeline producers stop, while driver handles and
    /// the directory/path still exist. Also retries a failed earlier save.
    pub fn finish(self: *Saver, source: Source) void {
        self.join();
        _ = self.request(source);
        self.join();
    }

    fn reap(self: *Saver, wait: bool) void {
        const job = self.job orelse return;
        if (!wait and !job.done.load(.acquire)) return;
        job.thread.?.join();
        if (job.saved) {
            self.persisted_generation = job.source.generation;
            self.last_failure = null;
        } else if (job.failure) |failure| {
            // Failed snapshots retain the old file and retry later. Make disk
            // exhaustion and other failures visible without repeating the same
            // warning at every checkpoint while the condition persists.
            const repeated = if (self.last_failure) |previous| previous == failure else false;
            if (!repeated) std.debug.print(
                "[vulkan cache] snapshot {s} failed: {s}; previous cache retained, will retry\n",
                .{ @tagName(job.phase), @errorName(failure) },
            );
            self.last_failure = failure;
        }
        std.heap.page_allocator.destroy(job);
        self.job = null;
    }
};

const Job = struct {
    source: Source,
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),
    saved: bool = false,
    failure: ?anyerror = null,
    phase: enum { query, allocate, extract, create, resize, map, write, replace } = .query,

    fn run(self: *Job) void {
        defer self.done.store(true, .release);
        self.save() catch |err| {
            self.failure = err;
        };
    }

    fn save(self: *Job) !void {
        const source = self.source;
        var data_size: usize = 0;
        if (source.get_data(source.device, source.cache, &data_size, null) != vk.success) return error.CacheSizeQueryFailed;
        if (data_size == 0) return;
        if (data_size > source.maximum_bytes) return error.CacheSizeLimitExceeded;
        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        // Keep the last complete cache if extraction or writing fails. Each
        // writer uses a separate temporary file, including concurrent processes.
        var path_buffer: [1024]u8 = undefined;
        var suffix: u64 = undefined;
        io.random(std.mem.asBytes(&suffix));
        self.phase = .create;
        const temporary = try std.fmt.bufPrint(&path_buffer, "{s}.{x}.tmp", .{ source.path, suffix });
        const file = try source.directory.createFile(io, temporary, .{ .exclusive = true, .read = true });
        defer source.directory.deleteFile(io, temporary) catch {};
        {
            defer file.close(io);
            if (builtin.os.tag == .windows and data_size >= source.mapped_file_threshold) {
                self.phase = .resize;
                try file.setLength(io, data_size);
                {
                    self.phase = .map;
                    const mapping = try WindowsFileMapping.init(file, data_size);
                    defer mapping.deinit();
                    try self.extract(mapping.bytes, &data_size);
                    self.phase = .write;
                    try mapping.flush(data_size);
                }
                // The driver may return fewer bytes than its initial query.
                // Windows requires the view to be unmapped before truncation.
                self.phase = .resize;
                try file.setLength(io, data_size);
            } else {
                self.phase = .allocate;
                const bytes = try std.heap.page_allocator.alloc(u8, data_size);
                defer std.heap.page_allocator.free(bytes);
                try self.extract(bytes, &data_size);
                self.phase = .write;
                try file.writePositionalAll(io, bytes[0..data_size], 0);
            }
        }
        self.phase = .replace;
        try source.directory.rename(temporary, source.directory, source.path, io);
        self.saved = true;
        if (data_size > 256 * 1024 * 1024)
            std.debug.print("[vulkan cache] persisted {d} MiB driver pipeline cache asynchronously\n", .{data_size / (1024 * 1024)});
    }

    fn extract(self: *Job, bytes: []u8, size: *usize) !void {
        self.phase = .extract;
        const source = self.source;
        if (source.get_data(source.device, source.cache, size, bytes.ptr) != vk.success) return error.CacheExtractionFailed;
        if (size.* == 0 or size.* > bytes.len) return error.InvalidCacheSize;
    }
};

const WindowsFileMapping = struct {
    handle: std.os.windows.HANDLE,
    bytes: []u8,

    extern "kernel32" fn CreateFileMappingW(std.os.windows.HANDLE, ?*const anyopaque, u32, u32, u32, ?[*:0]const u16) callconv(.winapi) ?std.os.windows.HANDLE;
    extern "kernel32" fn MapViewOfFile(std.os.windows.HANDLE, u32, u32, u32, usize) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn UnmapViewOfFile(*const anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn FlushViewOfFile(*const anyopaque, usize) callconv(.winapi) i32;

    fn init(file: std.Io.File, size: usize) !WindowsFileMapping {
        // PAGE_READWRITE, FILE_MAP_WRITE. This is a data-file-backed section,
        // not a page-file section or a copy-on-write mapping.
        const handle = CreateFileMappingW(file.handle, null, 0x04, 0, 0, null) orelse return error.CacheMappingFailed;
        errdefer std.os.windows.CloseHandle(handle);
        const address = MapViewOfFile(handle, 0x0002, 0, 0, size) orelse return error.CacheMappingFailed;
        return .{ .handle = handle, .bytes = @as([*]u8, @ptrCast(address))[0..size] };
    }

    fn flush(self: WindowsFileMapping, written: usize) !void {
        if (FlushViewOfFile(self.bytes.ptr, written) == 0) return error.CacheWriteFailed;
    }

    fn deinit(self: WindowsFileMapping) void {
        _ = UnmapViewOfFile(self.bytes.ptr);
        std.os.windows.CloseHandle(self.handle);
    }
};

const TestDriver = struct {
    entered: std.atomic.Value(bool) = .init(false),
    released: std.atomic.Value(bool) = .init(false),
    reads: std.atomic.Value(u32) = .init(0),
    fail: bool = false,
    invalid_size: bool = false,

    fn get(device: vk.Device, _: vk.PipelineCache, size: *usize, data: ?*anyopaque) callconv(vk.call) vk.Result {
        const self: *TestDriver = @ptrCast(@alignCast(device));
        self.entered.store(true, .release);
        while (!self.released.load(.acquire)) std.Thread.yield() catch {};
        if (data) |destination| {
            _ = self.reads.fetchAdd(1, .monotonic);
            if (self.fail) return vk.error_device_lost;
            if (self.invalid_size) {
                size.* += 1;
                return vk.success;
            }
            const value = "complete snapshot";
            if (size.* < value.len) return vk.error_device_lost;
            @memcpy(@as([*]u8, @ptrCast(destination))[0..value.len], value);
            // Drivers may write fewer bytes than the initial size query.
            size.* = value.len;
        } else size.* = 64;
        return vk.success;
    }
};

test "mapped pipeline snapshots preserve the old cache on failure and truncate to the written length" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache.bin", .data = "previous complete cache" });
    var driver = TestDriver{ .released = .init(true), .fail = true };
    var saver = Saver{};
    defer saver.join();
    const source = Source{ .device = @ptrCast(&driver), .cache = 1, .get_data = TestDriver.get, .generation = 1, .maximum_bytes = 128, .mapped_file_threshold = 0, .directory = temporary.dir, .path = "cache.bin" };
    saver.finish(source);
    try std.testing.expectEqual(error.CacheExtractionFailed, saver.last_failure.?);
    driver.fail = false;
    driver.invalid_size = true;
    saver.finish(source);
    try std.testing.expectEqual(error.InvalidCacheSize, saver.last_failure.?);
    try std.testing.expectEqual(@as(u64, 0), saver.persisted_generation);
    const before = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(before);
    try std.testing.expectEqualSlices(u8, "previous complete cache", before);
    driver.invalid_size = false;
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 1), saver.persisted_generation);
    try std.testing.expectEqual(null, saver.last_failure);
    const after = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, "complete snapshot", after);
}

test "pipeline cache saving returns while extraction waits and retains sampled generation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var driver = TestDriver{};
    var saver = Saver{};
    defer {
        driver.released.store(true, .release);
        saver.join();
    }
    var source = Source{ .device = @ptrCast(&driver), .cache = 1, .get_data = TestDriver.get, .generation = 1, .maximum_bytes = 128, .directory = temporary.dir, .path = "cache.bin" };
    try std.testing.expect(saver.request(source));
    while (!driver.entered.load(.acquire)) std.Thread.yield() catch {};
    source.generation = 2;
    try std.testing.expect(!saver.request(source));
    try std.testing.expectEqual(@as(u64, 0), saver.persisted_generation);
    driver.released.store(true, .release);
    saver.join();
    try std.testing.expectEqual(@as(u64, 1), saver.persisted_generation);
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 2), saver.persisted_generation);
    try std.testing.expectEqual(@as(u32, 2), driver.reads.load(.acquire));
    try std.testing.expect(!saver.request(source));
    const bytes = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, "complete snapshot", bytes);
}

test "failed and oversized pipeline snapshots preserve the previous file and retry" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache.bin", .data = "old cache" });
    var driver = TestDriver{ .released = .init(true), .fail = true };
    var saver = Saver{};
    defer saver.join();
    var source = Source{ .device = @ptrCast(&driver), .cache = 1, .get_data = TestDriver.get, .generation = 1, .maximum_bytes = 128, .directory = temporary.dir, .path = "cache.bin" };
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 0), saver.persisted_generation);
    try std.testing.expectEqual(error.CacheExtractionFailed, saver.last_failure.?);
    source.maximum_bytes = 32;
    driver.fail = false;
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 0), saver.persisted_generation);
    try std.testing.expectEqual(error.CacheSizeLimitExceeded, saver.last_failure.?);
    const before = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(before);
    try std.testing.expectEqualSlices(u8, "old cache", before);
    source.maximum_bytes = 128;
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 1), saver.persisted_generation);
    try std.testing.expectEqual(null, saver.last_failure);
    const after = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, "complete snapshot", after);
}

test "pipeline cache reports an unwritable destination and clears failure after retry" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache.bin", .data = "old cache" });
    var driver = TestDriver{ .released = .init(true) };
    var saver = Saver{};
    defer saver.join();
    var source = Source{ .device = @ptrCast(&driver), .cache = 1, .get_data = TestDriver.get, .generation = 1, .maximum_bytes = 128, .directory = temporary.dir, .path = "missing/cache.bin" };
    saver.finish(source);
    try std.testing.expect(saver.last_failure != null);
    try std.testing.expectEqual(@as(u64, 0), saver.persisted_generation);
    const before = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(before);
    try std.testing.expectEqualSlices(u8, "old cache", before);
    source.path = "cache.bin";
    saver.finish(source);
    try std.testing.expectEqual(null, saver.last_failure);
    try std.testing.expectEqual(@as(u64, 1), saver.persisted_generation);
    const after = try temporary.dir.readFileAlloc(std.testing.io, "cache.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, "complete snapshot", after);
}

test "pipeline cache checkpoints persist loading progress without flips and coalesce busy writes" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var driver = TestDriver{ .released = .init(true) };
    var saver = Saver{};
    defer {
        driver.released.store(true, .release);
        saver.join();
    }
    var source = Source{ .device = @ptrCast(&driver), .cache = 1, .get_data = TestDriver.get, .generation = 0, .maximum_bytes = 128, .directory = temporary.dir, .path = "cache.bin" };
    const second = std.time.ns_per_s;
    try std.testing.expect(!saver.checkpoint(source, 0));
    source.generation = 1;
    try std.testing.expect(saver.checkpoint(source, second));
    saver.join();
    source.generation = 2;
    try std.testing.expect(!saver.checkpoint(source, 30 * second));
    try std.testing.expectEqual(@as(u32, 1), driver.reads.load(.acquire));

    driver.entered.store(false, .release);
    driver.released.store(false, .release);
    try std.testing.expect(saver.checkpoint(source, 31 * second));
    while (!driver.entered.load(.acquire)) std.Thread.yield() catch {};
    source.generation = 3;
    try std.testing.expect(!saver.checkpoint(source, 90 * second));
    driver.released.store(true, .release);
    saver.join();
    try std.testing.expectEqual(@as(u64, 2), saver.persisted_generation);
    // A busy writer must not postpone the newer generation's deadline.
    try std.testing.expect(saver.checkpoint(source, 90 * second));
    saver.join();
    try std.testing.expectEqual(@as(u64, 3), saver.persisted_generation);
    try std.testing.expect(!saver.checkpoint(source, 120 * second));
    try std.testing.expectEqual(@as(u32, 3), driver.reads.load(.acquire));
    // Shutdown still saves the tail before the next periodic deadline.
    source.generation = 4;
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 4), saver.persisted_generation);
}

test "pipeline cache header validation accepts matching driver and rejects mismatches" {
    var uuid: [16]u8 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const header = Header{
        .header_size = 32,
        .header_version = 1,
        .vendor_id = 0x10de, // NVIDIA
        .device_id = 0x25a0,
        .pipeline_cache_uuid = uuid,
    };
    var buffer: [64]u8 = @splat(0);
    try header.write(buffer[0..32]);

    // Matching header passes validation
    try std.testing.expect(Header.validate(buffer[0..64], 0x10de, 0x25a0, &uuid));

    // Vendor mismatch fails
    try std.testing.expect(!Header.validate(buffer[0..64], 0x1002, 0x25a0, &uuid));

    // Device mismatch fails
    try std.testing.expect(!Header.validate(buffer[0..64], 0x10de, 0x9999, &uuid));

    // UUID mismatch fails
    var other_uuid = uuid;
    other_uuid[0] ^= 0xff;
    try std.testing.expect(!Header.validate(buffer[0..64], 0x10de, 0x25a0, &other_uuid));

    // Truncated buffer fails
    try std.testing.expect(!Header.validate(buffer[0..16], 0x10de, 0x25a0, &uuid));

    // Wrong version fails
    std.mem.writeInt(u32, buffer[4..8], 2, .little);
    try std.testing.expect(!Header.validate(buffer[0..64], 0x10de, 0x25a0, &uuid));
}

test "pipeline cache saver saves to nested paths when parent directory exists" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var driver = TestDriver{ .released = .init(true) };
    var saver = Saver{};
    defer saver.join();
    const nested_path = "nested/cache/dir/cache.bin";
    try temporary.dir.createDirPath(std.testing.io, "nested/cache/dir");
    const source = Source{
        .device = @ptrCast(&driver),
        .cache = 1,
        .get_data = TestDriver.get,
        .generation = 1,
        .maximum_bytes = 128,
        .directory = temporary.dir,
        .path = nested_path,
    };
    saver.finish(source);
    try std.testing.expectEqual(@as(u64, 1), saver.persisted_generation);
    try std.testing.expectEqual(null, saver.last_failure);
    const after = try temporary.dir.readFileAlloc(std.testing.io, nested_path, std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, "complete snapshot", after);
}

