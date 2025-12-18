const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const TreeFreelist = ost.OrderStatisticTree(i32, cmpI32, .{ .use_freelist = true });
const TreeNoFreelist = ost.OrderStatisticTree(i32, cmpI32, .{ .use_freelist = false });

const Snapshot = struct {
    alloc_calls: u64,
    free_calls: u64,
    total_alloc_bytes: u64,
    current_bytes: u64,
    peak_bytes: u64,
};

const Delta = struct {
    alloc_calls: u64,
    free_calls: u64,
    total_alloc_bytes: u64,
    current_bytes_end: u64,
    peak_bytes_end: u64,
};

const TrackingAllocator = struct {
    parent: std.mem.Allocator,

    alloc_calls: u64 = 0,
    free_calls: u64 = 0,
    total_alloc_bytes: u64 = 0,

    current_bytes: u64 = 0,
    peak_bytes: u64 = 0,

    fn init(parent: std.mem.Allocator) TrackingAllocator {
        return .{ .parent = parent };
    }

    fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn snap(self: *const TrackingAllocator) Snapshot {
        return .{
            .alloc_calls = self.alloc_calls,
            .free_calls = self.free_calls,
            .total_alloc_bytes = self.total_alloc_bytes,
            .current_bytes = self.current_bytes,
            .peak_bytes = self.peak_bytes,
        };
    }

    fn diff(self: *const TrackingAllocator, start: Snapshot) Delta {
        return .{
            .alloc_calls = self.alloc_calls - start.alloc_calls,
            .free_calls = self.free_calls - start.free_calls,
            .total_alloc_bytes = self.total_alloc_bytes - start.total_alloc_bytes,
            .current_bytes_end = self.current_bytes,
            .peak_bytes_end = self.peak_bytes,
        };
    }

    fn bumpPeak(self: *TrackingAllocator) void {
        if (self.current_bytes > self.peak_bytes) self.peak_bytes = self.current_bytes;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.parent.rawAlloc(len, alignment, ret_addr);
        if (p != null) {
            self.alloc_calls += 1;
            self.total_alloc_bytes += @intCast(len);
            self.current_bytes += @intCast(len);
            self.bumpPeak();
        }
        return p;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        self.free_calls += 1;
        self.current_bytes -= @intCast(buf.len);
        self.parent.rawFree(buf, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.parent.rawResize(buf, alignment, new_len, ret_addr);
        if (ok) {
            if (new_len > buf.len) {
                const delta: u64 = @intCast(new_len - buf.len);
                self.total_alloc_bytes += delta;
                self.current_bytes += delta;
                self.bumpPeak();
            } else {
                const delta: u64 = @intCast(buf.len - new_len);
                self.current_bytes -= delta;
            }
        }
        return ok;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.parent.rawRemap(buf, alignment, new_len, ret_addr);
        if (p != null) {
            if (new_len > buf.len) {
                const delta: u64 = @intCast(new_len - buf.len);
                self.total_alloc_bytes += delta;
                self.current_bytes += delta;
                self.bumpPeak();
            } else {
                const delta: u64 = @intCast(buf.len - new_len);
                self.current_bytes -= delta;
            }
        }
        return p;
    }
};

fn writeCsvLine(file: *std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, fmt, args);
    try file.writeAll(line);
}

fn fisherYatesShuffle(rng: *std.Random, data: []i32) void {
    var i: usize = data.len;
    while (i > 1) {
        i -= 1;
        const j = rng.uintLessThan(usize, i + 1);
        const tmp = data[i];
        data[i] = data[j];
        data[j] = tmp;
    }
}

fn buildKeyArray(allocator: std.mem.Allocator, n: usize) ![]i32 {
    var keys = try allocator.alloc(i32, n);
    var i: usize = 0;
    while (i < n) : (i += 1) keys[i] = @intCast(i);
    return keys;
}

fn writeRow(
    out: *std.fs.File,
    test_name: []const u8,
    config_name: []const u8,
    n: usize,
    ops: u64,
    ns: u64,
    bytes_before: u64,
    bytes_after: u64,
    d: Delta,
) !void {
    const seconds: f64 = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    const ops_per_sec: f64 = if (seconds > 0) @as(f64, @floatFromInt(ops)) / seconds else 0.0;

    try writeCsvLine(
        out,
        "{s},{s},{d},{d},{d:.9},{d:.3},{d},{d},{d},{d},{d},{d},{d}\n",
        .{
            test_name,
            config_name,
            n,
            ops,
            seconds,
            ops_per_sec,
            d.alloc_calls,
            d.free_calls,
            d.total_alloc_bytes,
            bytes_before,
            bytes_after,
            d.current_bytes_end,
            d.peak_bytes_end,
        },
    );

    std.debug.print(
        "{s:>22} | {s:>11} | n={d:>8} | ops/s={d:>10.0} | bytes {d}->{d} | alloc={d} free={d}\n",
        .{ test_name, config_name, n, ops_per_sec, bytes_before, bytes_after, d.alloc_calls, d.free_calls },
    );
}

fn runQueries(
    comptime TreeType: type,
    config_name: []const u8,
    base_alloc: std.mem.Allocator,
    out: *std.fs.File,
    keys: []const i32,
    rng: *std.Random,
    target_ns: u64,
) !void {
    var tracker = TrackingAllocator.init(base_alloc);
    const a = tracker.allocator();

    var tree = TreeType.init(a);
    defer tree.deinit();

    // Build (separate row)
    {
        const snap0 = tracker.snap();
        const bytes0 = tracker.current_bytes;

        var t = try std.time.Timer.start();
        for (keys) |k| try tree.insert(k);
        const ns = t.read();

        const bytes1 = tracker.current_bytes;
        const d = tracker.diff(snap0);
        try writeRow(out, "insert_build", config_name, keys.len, @intCast(keys.len), ns, bytes0, bytes1, d);
    }

    const bytes_after_build = tracker.current_bytes;

    // SEARCH timed (operation-only)
    {
        const snap0 = tracker.snap();
        var t = try std.time.Timer.start();
        var ops: u64 = 0;
        while (t.read() < target_ns) {
            const idx = rng.uintLessThan(usize, keys.len);
            _ = tree.search(keys[idx]);
            ops += 1;
        }
        const ns = t.read();
        const d = tracker.diff(snap0);
        try writeRow(out, "search", config_name, keys.len, ops, ns, bytes_after_build, bytes_after_build, d);
    }

    // SELECT timed
    {
        const snap0 = tracker.snap();
        var t = try std.time.Timer.start();
        var ops: u64 = 0;
        while (t.read() < target_ns) {
            const idx = rng.uintLessThan(usize, keys.len);
            _ = tree.select(idx);
            ops += 1;
        }
        const ns = t.read();
        const d = tracker.diff(snap0);
        try writeRow(out, "select", config_name, keys.len, ops, ns, bytes_after_build, bytes_after_build, d);
    }

    // SUCCESSOR timed
    {
        const snap0 = tracker.snap();
        var t = try std.time.Timer.start();
        var ops: u64 = 0;
        while (t.read() < target_ns) {
            const idx = rng.uintLessThan(usize, keys.len);
            _ = tree.successor(keys[idx]);
            ops += 1;
        }
        const ns = t.read();
        const d = tracker.diff(snap0);
        try writeRow(out, "successor", config_name, keys.len, ops, ns, bytes_after_build, bytes_after_build, d);
    }
}

fn runDeleteToEmpty(
    comptime TreeType: type,
    config_name: []const u8,
    base_alloc: std.mem.Allocator,
    out: *std.fs.File,
    keys: []const i32,
) !void {
    var tracker = TrackingAllocator.init(base_alloc);
    const a = tracker.allocator();

    var tree = TreeType.init(a);
    defer tree.deinit();

    for (keys) |k| try tree.insert(k);
    const bytes_before_delete = tracker.current_bytes;

    const snap0 = tracker.snap();
    var t = try std.time.Timer.start();
    for (keys) |k| tree.delete(k);
    const ns = t.read();

    const bytes_after_delete = tracker.current_bytes;

    const d = tracker.diff(snap0);
    try writeRow(out, "delete_to_empty", config_name, keys.len, @intCast(keys.len), ns, bytes_before_delete, bytes_after_delete, d);
}

fn runChurn(
    comptime TreeType: type,
    config_name: []const u8,
    base_alloc: std.mem.Allocator,
    tmp_alloc: std.mem.Allocator,
    out: *std.fs.File,
    keys: []const i32,
    rng: *std.Random,
    churn_pairs: usize,
) !void {
    var tracker = TrackingAllocator.init(base_alloc);
    const a = tracker.allocator();

    var tree = TreeType.init(a);
    defer tree.deinit();

    // Build
    for (keys) |k| try tree.insert(k);
    const bytes_after_build = tracker.current_bytes;

    // Maintain a mutable “present set”
    const present = try tmp_alloc.alloc(i32, keys.len);
    std.mem.copyForwards(i32, present, keys);

    // Measure churn only
    const snap0 = tracker.snap();
    var next_key: i32 = @intCast(keys.len);

    var t = try std.time.Timer.start();
    var i: usize = 0;
    while (i < churn_pairs) : (i += 1) {
        const victim_idx = rng.uintLessThan(usize, present.len);
        const victim_key = present[victim_idx];
        tree.delete(victim_key);

        const new_key = next_key;
        next_key += 1;
        try tree.insert(new_key);

        present[victim_idx] = new_key;
    }
    const ns = t.read();

    const d = tracker.diff(snap0);
    const ops: u64 = @as(u64, @intCast(churn_pairs)) * 2;
    try writeRow(out, "churn_delete_insert", config_name, keys.len, ops, ns, bytes_after_build, tracker.current_bytes, d);
}

pub fn main() !void {
    var min_n: usize = 1_000;
    var max_n: usize = 4_000_000;
    var factor: usize = 2;

    var churn_pairs_per_n: usize = 200_000;
    var timed_target_ns: u64 = 200_000_000; // 200ms default (faster than 300ms)

    // Windows-safe args iterator
    var args_it = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args_it.deinit();

    _ = args_it.next();
    while (args_it.next()) |a| {
        if (std.mem.eql(u8, a, "--min")) min_n = try std.fmt.parseInt(usize, args_it.next().?, 10)
        else if (std.mem.eql(u8, a, "--max")) max_n = try std.fmt.parseInt(usize, args_it.next().?, 10)
        else if (std.mem.eql(u8, a, "--factor")) factor = try std.fmt.parseInt(usize, args_it.next().?, 10)
        else if (std.mem.eql(u8, a, "--churn")) churn_pairs_per_n = try std.fmt.parseInt(usize, args_it.next().?, 10)
        else if (std.mem.eql(u8, a, "--target_ms")) {
            const ms = try std.fmt.parseInt(u64, args_it.next().?, 10);
            timed_target_ns = ms * 1_000_000;
        }
    }

    std.debug.print("Profiling n={d}..{d} factor={d} target_ms={d} churn_pairs={d}\n",
        .{ min_n, max_n, factor, timed_target_ns / 1_000_000, churn_pairs_per_n });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const tmp_alloc = arena.allocator();

    var out = try std.fs.cwd().createFile("profile.csv", .{ .truncate = true });
    defer out.close();

    try out.writeAll(
        "test,config,n,ops,seconds,ops_per_sec,alloc_calls,free_calls,total_alloc_bytes,bytes_before,bytes_after,current_bytes,peak_bytes\n"
    );

    var prng = std.Random.DefaultPrng.init(0x1234_5678);
    var rng = prng.random();

    var n: usize = min_n;
    while (true) {
        std.debug.print("\n=== n = {d} ===\n", .{n});
        _ = arena.reset(.retain_capacity);

        const keys = try buildKeyArray(tmp_alloc, n);
        fisherYatesShuffle(&rng, keys);

        // freelist
        try runQueries(TreeFreelist, "freelist", gpa.allocator(), &out, keys, &rng, timed_target_ns);
        try runDeleteToEmpty(TreeFreelist, "freelist", gpa.allocator(), &out, keys);
        try runChurn(TreeFreelist, "freelist", gpa.allocator(), tmp_alloc, &out, keys, &rng, churn_pairs_per_n);

        // no freelist
        try runQueries(TreeNoFreelist, "no_freelist", gpa.allocator(), &out, keys, &rng, timed_target_ns);
        try runDeleteToEmpty(TreeNoFreelist, "no_freelist", gpa.allocator(), &out, keys);
        try runChurn(TreeNoFreelist, "no_freelist", gpa.allocator(), tmp_alloc, &out, keys, &rng, churn_pairs_per_n);

        if (n == max_n) break;
        const next = n * factor;
        if (next <= n or next >= max_n) n = max_n else n = next;
    }

    std.debug.print("\nDONE. Wrote profile.csv\n", .{});
}
