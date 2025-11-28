const std = @import("std");
const ost = @import("ost");

const CSV = false;

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const Tree = ost.OrderStatisticTree(i32, cmpI32);

const OperationResult = struct {
    operation: []const u8,
    elems: usize,
    ns: u64,
};

pub fn main() !void {
    const N: usize = 100_000;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results: [3]OperationResult = undefined;
    var count: usize = 0;

    {
        var tree = Tree.init(allocator);
        defer tree.deinit();

        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < N) : (i += 1) {
            try tree.insert(@intCast(i));
        }
        const ns = timer.read();

        results[count] = .{
            .operation = "insert",
            .elems = N,
            .ns = ns,
        };
        count += 1;
    }

    {
        var tree = Tree.init(allocator);
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

        results[count] = .{
            .operation = "search",
            .elems = N,
            .ns = ns,
        };
        count += 1;
    }

    {
        var tree = Tree.init(allocator);
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

        results[count] = .{
            .operation = "delete",
            .elems = N,
            .ns = ns,
        };
        count += 1;
    }

    try printResults(results[0..count]);
    if (CSV) try writeCsv("benchmark_results.csv", results[0..count]);
}

fn printResults(results: []const OperationResult) !void {
    std.debug.print("Benchmark results\n", .{});
    std.debug.print("1 Element = i32\n\n", .{});
    for (results) |r| {
        const ns_f = @as(f64, @floatFromInt(r.ns));
        const elems_f = @as(f64, @floatFromInt(r.elems));

        const per_ns = elems_f / ns_f;
        const per_ms = per_ns * 1_000_000.0;
        const per_s = per_ns * 1_000_000_000.0;

        std.debug.print(
            "[{s}]\n  > {d:.6} elems/ns | {d:.2} elems/ms | {d:.2} elems/s\n",
            .{ r.operation, per_ns, per_ms, per_s },
        );
        std.debug.print("{s} of 5.000.000 Elements in {}s\n\n", .{ r.operation, 5_000_000 / per_s });
    }
}

fn writeCsv(path: []const u8, results: []const OperationResult) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll("operation,elems,ns,per_ns,per_ms,per_s\n");

    var buf: [256]u8 = undefined;

    for (results) |r| {
        const ns_f = @as(f64, @floatFromInt(r.ns));
        const elems_f = @as(f64, @floatFromInt(r.elems));

        const per_ns = elems_f / ns_f;
        const per_ms = per_ns * 1_000_000.0;
        const per_s = per_ns * 1_000_000_000.0;

        const line = try std.fmt.bufPrint(
            &buf,
            "{s},{d},{d},{d:.6},{d:.2},{d:.2}\n",
            .{ r.operation, r.elems, r.ns, per_ns, per_ms, per_s },
        );
        try file.writeAll(line);
    }
}
