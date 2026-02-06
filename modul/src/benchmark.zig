//! Red-Black Tree Benchmark Suite
//!
//! Comprehensive performance benchmarking for Red-Black Tree implementation.
//! Measures time and memory usage for various operations, comparing base vs pooled configurations.
//!
//! Output: bench.csv with columns: n, variant, op, sample, ns_per_op, mem_peak_bytes, expected_node_bytes
//! Usage: zig build -Doptimize=ReleaseFast && ./zig-out/bin/benchmark

const std = @import("std");
const rb = @import("rb_tree");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

// =====================
// CONFIG (nur dafür)
// =====================
const PRINT_HUMAN: bool = true;
const WRITE_CSV: bool = true;
const CSV_PATH: []const u8 = "bench.csv";

// Viele Punkte => schöne Kurven
const SIZES = [_]usize{ 1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000 };

// Stabile Messung
const WARMUP_ITERS: usize = 2;
const SAMPLES: usize = 25;

// Diese 3 reichen für 1.3 (Zeit + Speedup + Speicher)
const DO_SEARCH_HIT: bool = true; // O(log n)
const DO_PREDECESSOR: bool = true; // O(log n), thematisch passend
const DO_CYCLES: bool = true; // zeigt Pooling-Speedup deutlich
const DO_MEM_INSERT_PEAK: bool = true; // O(n) Speicher

// Configs: Opt = Pooling AN, aber Stats AUS (Stats verfälschen sonst Timing)
const BaseTree = rb.Tree(i32, .{
    .enable_pool = false,
    .enable_stats = false,
    .enable_minmax_cache = true,
});
const OptTree = rb.Tree(i32, .{
    .enable_pool = true,
    .max_pool_size = 1000,
    .enable_stats = false,
    .enable_minmax_cache = true,
});

// Ziel: ca. gleich viele Operationen je n im cycles-bench
const TARGET_CYCLE_OPS: usize = 2_000_000; // total ops ~2M (insert+delete)

// =====================
// ------------------------------
// CountingAllocator (requested bytes, peak)
// ------------------------------
const CountingAllocator = struct {
    child: Allocator,
    live_bytes: usize = 0,
    peak_live_bytes: usize = 0,

    pub fn init(child: Allocator) CountingAllocator {
        return .{ .child = child };
    }

    pub fn allocator(self: *CountingAllocator) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const Alignment = std.mem.Alignment;
    const vtable = Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };
    fn bumpAlloc(self: *CountingAllocator, delta: usize) void {
        self.live_bytes += delta;
        if (self.live_bytes > self.peak_live_bytes) self.peak_live_bytes = self.live_bytes;
    }

    fn bumpFree(self: *CountingAllocator, delta: usize) void {
        self.live_bytes -= delta;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.child.vtable.alloc(self.child.ptr, len, alignment, ret_addr) orelse return null;
        self.bumpAlloc(len);
        return p;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = memory.len;
        const ok = self.child.vtable.resize(self.child.ptr, memory, alignment, new_len, ret_addr);
        if (!ok) return false;
        if (new_len > old_len) self.bumpAlloc(new_len - old_len) else self.bumpFree(old_len - new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = memory.len;
        const p = self.child.vtable.remap(self.child.ptr, memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > old_len) self.bumpAlloc(new_len - old_len) else self.bumpFree(old_len - new_len);
        return p;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.vtable.free(self.child.ptr, memory, alignment, ret_addr);
        self.bumpFree(memory.len);
    }
};

// ------------------------------
// CSV (Samples + Memory)
// ------------------------------
fn csvHeader(w: *Writer) !void {
    try w.writeAll("n,variant,op,sample,ns_per_op,mem_peak_bytes,expected_node_bytes\n");
}

fn csvRow(
    w: *Writer,
    n: usize,
    variant: []const u8,
    op: []const u8,
    sample: usize,
    ns_per_op: u64,
    mem_peak_bytes: usize,
    expected_node_bytes: usize,
) !void {
    try w.print("{},{s},{s},{},{},{},{}\n", .{ n, variant, op, sample, ns_per_op, mem_peak_bytes, expected_node_bytes });
}

// dataset: even values
inline fn valueAt(i: usize) i32 {
    return @intCast(i * 2);
}

fn fillTree(tree: anytype, n: usize) !void {
    for (0..n) |i| try tree.insert(valueAt(i));
}

// ------------------------------
// Workload functions (return checksum)
// ------------------------------
fn workSearchHit(tree: anytype, n: usize) usize {
    var acc: usize = 0;
    for (0..n) |i| if (tree.search(valueAt(i))) {
        acc += 1;
    };
    std.mem.doNotOptimizeAway(acc);
    return acc;
}

fn workPredecessor(tree: anytype, n: usize) i64 {
    var acc: i64 = 0;
    for (0..n) |i| {
        const q: i32 = @intCast(i * 2 + 1);
        const p = tree.predecessor(q);
        if (p[0] != -1) acc += p[0] + p[1];
    }
    std.mem.doNotOptimizeAway(acc);
    return acc;
}

fn workCyclesInsertDelete(tree: anytype, n: usize, cycles: usize) i64 {
    var acc: i64 = 0;
    for (0..cycles) |c| {
        _ = c;
        for (0..n) |i| tryInsert(tree, @intCast(i * 2));
        for (0..n) |i| {
            const v: i32 = @intCast(i * 2);
            tree.delete(v);
            acc += v;
        }
    }
    std.mem.doNotOptimizeAway(acc);
    return acc;
}

inline fn tryInsert(tree: anytype, v: i32) void {
    // tree.insert is !void
    tree.insert(v) catch unreachable;
}

// ------------------------------
// Timing helpers (interleaved samples)
// ------------------------------
fn timeNsPerOpSearchHit(tree: anytype, n: usize) !u64 {
    var timer = try std.time.Timer.start();
    _ = workSearchHit(tree, n);
    const ns = timer.read();
    return ns / @max(@as(u64, 1), @as(u64, @intCast(n)));
}

fn timeNsPerOpPredecessor(tree: anytype, n: usize) !u64 {
    var timer = try std.time.Timer.start();
    _ = workPredecessor(tree, n);
    const ns = timer.read();
    return ns / @max(@as(u64, 1), @as(u64, @intCast(n)));
}

fn cyclesForN(n: usize) usize {
    const denom = @max(@as(usize, 1), 2 * n);
    const c = TARGET_CYCLE_OPS / denom;
    return std.math.clamp(c, 1, 2000);
}

fn timeNsPerOpCycles(tree: anytype, n: usize, cycles: usize) !u64 {
    const ops_total: u64 = @intCast(2 * n * cycles);
    var timer = try std.time.Timer.start();
    _ = workCyclesInsertDelete(tree, n, cycles);
    const ns = timer.read();
    return ns / @max(@as(u64, 1), ops_total);
}

// ------------------------------
// Main
// ------------------------------
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // stdout writer
    var out: ?*Writer = null;
    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_wr: @TypeOf(std.fs.File.stdout().writer(&stdout_buf)) = undefined;
    if (PRINT_HUMAN) {
        stdout_wr = std.fs.File.stdout().writer(&stdout_buf);
        out = &stdout_wr.interface;
        defer out.?.flush() catch {};
        try out.?.writeAll("=== Evaluation Bench (interleaved samples + paired speedup) ===\n");
        try out.?.print("sizes={any}, warmup={}, samples={}\n\n", .{ SIZES, WARMUP_ITERS, SAMPLES });
    }

    if (!WRITE_CSV) return;
    const f = try std.fs.cwd().createFile(CSV_PATH, .{ .truncate = true });
    defer f.close();
    var csv_buf: [64 * 1024]u8 = undefined;
    var csv_wr = f.writer(&csv_buf);
    const csv = &csv_wr.interface;
    defer csv.flush() catch {};
    try csvHeader(csv);

    for (SIZES) |n| {
        if (PRINT_HUMAN) try out.?.print("---- n = {} ----\n", .{n});

        // Pre-fill once for search/predecessor timing
        var base_prefill = BaseTree.init(alloc);
        defer base_prefill.deinit();
        var opt_prefill = OptTree.init(alloc);
        defer opt_prefill.deinit();
        try fillTree(&base_prefill, n);
        try fillTree(&opt_prefill, n);

        if (DO_SEARCH_HIT) {
            for (0..WARMUP_ITERS) |_| {
                _ = workSearchHit(&base_prefill, n);
                _ = workSearchHit(&opt_prefill, n);
            }

            for (0..SAMPLES) |s| {
                const base_first = (s % 2 == 0);
                if (base_first) {
                    const b = try timeNsPerOpSearchHit(&base_prefill, n);
                    const o = try timeNsPerOpSearchHit(&opt_prefill, n);
                    try csvRow(csv, n, "base", "time_search_hit", s, b, 0, 0);
                    try csvRow(csv, n, "opt", "time_search_hit", s, o, 0, 0);
                } else {
                    const o = try timeNsPerOpSearchHit(&opt_prefill, n);
                    const b = try timeNsPerOpSearchHit(&base_prefill, n);
                    try csvRow(csv, n, "opt", "time_search_hit", s, o, 0, 0);
                    try csvRow(csv, n, "base", "time_search_hit", s, b, 0, 0);
                }
            }
            if (PRINT_HUMAN) try out.?.writeAll(" wrote: time_search_hit samples\n");
        }

        if (DO_PREDECESSOR) {
            for (0..WARMUP_ITERS) |_| {
                _ = workPredecessor(&base_prefill, n);
                _ = workPredecessor(&opt_prefill, n);
            }

            for (0..SAMPLES) |s| {
                const base_first = (s % 2 == 0);
                if (base_first) {
                    const b = try timeNsPerOpPredecessor(&base_prefill, n);
                    const o = try timeNsPerOpPredecessor(&opt_prefill, n);
                    try csvRow(csv, n, "base", "time_predecessor", s, b, 0, 0);
                    try csvRow(csv, n, "opt", "time_predecessor", s, o, 0, 0);
                } else {
                    const o = try timeNsPerOpPredecessor(&opt_prefill, n);
                    const b = try timeNsPerOpPredecessor(&base_prefill, n);
                    try csvRow(csv, n, "opt", "time_predecessor", s, o, 0, 0);
                    try csvRow(csv, n, "base", "time_predecessor", s, b, 0, 0);
                }
            }
            if (PRINT_HUMAN) try out.?.writeAll(" wrote: time_predecessor samples\n");
        }

        if (DO_CYCLES) {
            const cycles = cyclesForN(n);
            // warmup (fresh trees)
            for (0..WARMUP_ITERS) |_| {
                var tb = BaseTree.init(alloc);
                defer tb.deinit();
                var to = OptTree.init(alloc);
                defer to.deinit();
                _ = workCyclesInsertDelete(&tb, n, cycles);
                _ = workCyclesInsertDelete(&to, n, cycles);
            }

            for (0..SAMPLES) |s| {
                const base_first = (s % 2 == 0);
                if (base_first) {
                    var tb = BaseTree.init(alloc);
                    defer tb.deinit();
                    var to = OptTree.init(alloc);
                    defer to.deinit();
                    const b = try timeNsPerOpCycles(&tb, n, cycles);
                    const o = try timeNsPerOpCycles(&to, n, cycles);
                    try csvRow(csv, n, "base", "time_cycles_insert_delete", s, b, 0, 0);
                    try csvRow(csv, n, "opt", "time_cycles_insert_delete", s, o, 0, 0);
                } else {
                    var to = OptTree.init(alloc);
                    defer to.deinit();
                    var tb = BaseTree.init(alloc);
                    defer tb.deinit();
                    const o = try timeNsPerOpCycles(&to, n, cycles);
                    const b = try timeNsPerOpCycles(&tb, n, cycles);
                    try csvRow(csv, n, "opt", "time_cycles_insert_delete", s, o, 0, 0);
                    try csvRow(csv, n, "base", "time_cycles_insert_delete", s, b, 0, 0);
                }
            }
            if (PRINT_HUMAN) try out.?.print(" wrote: time_cycles_insert_delete samples (cycles={})\n", .{cycles});
        }

        if (DO_MEM_INSERT_PEAK) {
            try benchMemInsertPeak(BaseTree, "base", alloc, out, csv, n);
            try benchMemInsertPeak(OptTree, "opt", alloc, out, csv, n);
        }

        if (PRINT_HUMAN) try out.?.writeAll("\n");
    }

    if (PRINT_HUMAN) try out.?.print("Wrote CSV: {s}\n", .{CSV_PATH});
}

fn benchMemInsertPeak(
    comptime TreeType: type,
    variant: []const u8,
    base_alloc: Allocator,
    out: ?*Writer,
    csv: *Writer,
    n: usize,
) !void {
    var ca = CountingAllocator.init(base_alloc);
    var tree = TreeType.init(ca.allocator());
    defer tree.deinit();
    for (0..n) |i| try tree.insert(valueAt(i));
    const node_size = @sizeOf(TreeType.Node);
    const expected = n * node_size;
    try csvRow(csv, n, variant, "mem_insert_peak", 0, 0, ca.peak_live_bytes, expected);
    if (PRINT_HUMAN) {
        try out.?.print(" {s} mem_insert_peak: peak={} expected~{}\n", .{ variant, ca.peak_live_bytes, expected });
    }
}
