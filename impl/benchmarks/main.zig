const std = @import("std");
const ost = @import("ost");

const CSV = false;

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const TreeNoPool = ost.OrderStatisticTree(i32, cmpI32, .{ .use_freelist = false, .allocation_mode = .general });
const TreePool = ost.OrderStatisticTree(i32, cmpI32, .{ .use_freelist = true });

const Allocator = std.mem.Allocator;

const OperationResult = struct {
    scenario: []const u8, // "bulk" or "churn"
    tree_kind: []const u8, // "no_pool" or "freelist"
    operation: []const u8, // "insert", "search", "delete", "churn_cycle"
    elems: usize,
    ns: u64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results: [16]OperationResult = undefined;
    var count: usize = 0;

    // 1) Bulk throughput: N = 1_000_000
    const N_bulk: usize = 1_000_000;
    try benchBulk("bulk", "no_pool", TreeNoPool, allocator, N_bulk, &results, &count);
    try benchBulk("bulk", "freelist", TreePool, allocator, N_bulk, &results, &count);

    // 2) Churn benchmark: N = 5_000_000, then 4x (delete 200k, insert 200k)
    const N_churn: usize = 5_000_000;
    const batch: usize = 200_000;
    const cycles: usize = 15;
    try benchChurn("churn", "no_pool", TreeNoPool, allocator, N_churn, batch, cycles, &results, &count);
    try benchChurn("churn", "freelist", TreePool, allocator, N_churn, batch, cycles, &results, &count);

    try printResults(results[0..count]);
    if (CSV) try writeCsv("benchmark_results.csv", results[0..count]);
}

/// Scenario 1: bulk insert/search/delete.
fn benchBulk(
    scenario: []const u8,
    tree_kind: []const u8,
    comptime TreeType: type,
    allocator: Allocator,
    N: usize,
    results: *[16]OperationResult,
    count: *usize,
) !void {
    // INSERT
    {
        var tree = TreeType.init(allocator);
        defer tree.deinit();

        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < N) : (i += 1) {
            try tree.insert(@intCast(i));
        }
        const ns = timer.read();

        results[count.*] = .{
            .scenario = scenario,
            .tree_kind = tree_kind,
            .operation = "insert",
            .elems = N,
            .ns = ns,
        };
        count.* += 1;
    }

    // SEARCH
    {
        var tree = TreeType.init(allocator);
        defer tree.deinit();

        var i: usize = 0;
        while (i < N) : (i += 1) {
            try tree.insert(@intCast(i));
        }

        var timer = try std.time.Timer.start();
        i = 0;
        while (i < N) : (i += 1) {
            _ = tree.search(@intCast(i));
        }
        const ns = timer.read();

        results[count.*] = .{
            .scenario = scenario,
            .tree_kind = tree_kind,
            .operation = "search",
            .elems = N,
            .ns = ns,
        };
        count.* += 1;
    }

    // DELETE
    {
        var tree = TreeType.init(allocator);
        defer tree.deinit();

        var i: usize = 0;
        while (i < N) : (i += 1) {
            try tree.insert(@intCast(i));
        }

        var timer = try std.time.Timer.start();
        i = 0;
        while (i < N) : (i += 1) {
            tree.delete(@intCast(i));
        }
        const ns = timer.read();

        results[count.*] = .{
            .scenario = scenario,
            .tree_kind = tree_kind,
            .operation = "delete",
            .elems = N,
            .ns = ns,
        };
        count.* += 1;
    }
}

/// Scenario 2: insert N >> cycles × (delete batch, insert batch).
fn benchChurn(
    scenario: []const u8,
    tree_kind: []const u8,
    comptime TreeType: type,
    allocator: Allocator,
    N: usize,
    batch: usize,
    cycles: usize,
    results: *[16]OperationResult,
    count: *usize,
) !void {
    var tree = TreeType.init(allocator);
    defer tree.deinit();

    var i: usize = 0;
    while (i < N) : (i += 1) {
        try tree.insert(@intCast(i));
    }

    var timer = try std.time.Timer.start();

    var c: usize = 0;
    while (c < cycles) : (c += 1) {
        const base = c * batch;

        // delete batch
        i = 0;
        while (i < batch) : (i += 1) {
            const key: i32 = @intCast(base + i);
            tree.delete(key);
        }

        // insert batch
        i = 0;
        while (i < batch) : (i += 1) {
            const key: i32 = @intCast(base + i + N);
            try tree.insert(key);
        }
    }

    const ns = timer.read();
    const total_ops: usize = cycles * batch * 2; // delete + insert per cycle

    results[count.*] = .{
        .scenario = scenario,
        .tree_kind = tree_kind,
        .operation = "churn_cycle",
        .elems = total_ops,
        .ns = ns,
    };
    count.* += 1;
}

fn printResults(results: []const OperationResult) !void {
    std.debug.print("Benchmark results\n", .{});
    std.debug.print("1 Element = i32\n\n", .{});

    var churn_no_pool: ?OperationResult = null;
    var churn_freelist: ?OperationResult = null;

    for (results) |r| {
        const ns_f = @as(f64, @floatFromInt(r.ns));
        const elems_f = @as(f64, @floatFromInt(r.elems));

        const per_ns = elems_f / ns_f;
        const per_ms = per_ns * 1_000_000.0;
        const per_s = per_ns * 1_000_000_000.0;

        std.debug.print(
            "[{s}][{s}][{s}]\n  > {d:.6} elems/ns | {d:.2} elems/ms | {d:.2} elems/s\n",
            .{ r.scenario, r.operation, r.tree_kind, per_ns, per_ms, per_s },
        );
        std.debug.print(
            "{s} of {d} elements in {d:.6}s\n\n",
            .{ r.operation, r.elems, elems_f / per_s },
        );

        if (std.mem.eql(u8, r.scenario, "churn") and
            std.mem.eql(u8, r.operation, "churn_cycle"))
        {
            if (std.mem.eql(u8, r.tree_kind, "no_pool")) {
                churn_no_pool = r;
            } else if (std.mem.eql(u8, r.tree_kind, "freelist")) {
                churn_freelist = r;
            }
        }
    }

    if (churn_no_pool) |np| if (churn_freelist) |fl| {
        const np_ns = @as(f64, @floatFromInt(np.ns));
        const fl_ns = @as(f64, @floatFromInt(fl.ns));

        const speedup = np_ns / fl_ns;
        const percent = (speedup - 1.0) * 100.0;

        std.debug.print(
            "Churn freelist speedup: {d:.2}% faster\n",
            .{percent},
        );
    };
}

fn writeCsv(path: []const u8, results: []const OperationResult) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll("scenario,tree_kind,operation,elems,ns,per_ns,per_ms,per_s\n");

    var buf: [256]u8 = undefined;

    for (results) |r| {
        const ns_f = @as(f64, @floatFromInt(r.ns));
        const elems_f = @as(f64, @floatFromInt(r.elems));

        const per_ns = elems_f / ns_f;
        const per_ms = per_ns * 1_000_000.0;
        const per_s = per_ns * 1_000_000_000.0;

        const line = try std.fmt.bufPrint(
            &buf,
            "{s},{s},{s},{d},{d},{d:.6},{d:.2},{d:.2}\n",
            .{ r.scenario, r.tree_kind, r.operation, r.elems, r.ns, per_ns, per_ms, per_s },
        );
        try file.writeAll(line);
    }
}
