// benchmarks/profiling.zig
const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

// Use your default config; adjust if you want to compare variants (e.g. compact_sizes=true).
const TreeDefault = ost.OrderStatisticTree(i32, cmpI32, .{});

fn nodeSizeBytes() usize {
    return @sizeOf(TreeDefault.Node);
}

fn printCsv(file: *std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    var buf: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, fmt, args);
    try file.writeAll(line);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try std.fs.cwd().createFile("results.csv", .{ .truncate = true });
    defer file.close();

    try file.writeAll("operation,size,time_ns,memory_bytes\n");

    const sizes = [_]usize{ 1_000, 5_000, 10_000, 50_000, 100_000 };

    for (sizes) |n| {
        try profileInsert(allocator, n, &file);
        try profileSearch(allocator, n, &file);
        try profileDelete(allocator, n, &file);
        try profileSelect(allocator, n, &file);
        try profileSuccessor(allocator, n, &file);
    }
}

fn profileInsert(allocator: std.mem.Allocator, n: usize, file: *std.fs.File) !void {
    var tree = TreeDefault.init(allocator);
    defer tree.deinit();

    var t = try std.time.Timer.start();
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try tree.insert(@intCast(i));
    }
    const ns = t.read();

    try printCsv(file, "insert,{d},{d},{d}\n", .{ n, ns, n * nodeSizeBytes() });
}

fn profileSearch(allocator: std.mem.Allocator, n: usize, file: *std.fs.File) !void {
    var tree = TreeDefault.init(allocator);
    defer tree.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        try tree.insert(@intCast(i));
    }

    var t = try std.time.Timer.start();
    i = 0;
    while (i < n) : (i += 1) {
        _ = tree.search(@intCast(i));
    }
    const ns = t.read();

    try printCsv(file, "search,{d},{d},{d}\n", .{ n, ns, n * nodeSizeBytes() });
}

fn profileDelete(allocator: std.mem.Allocator, n: usize, file: *std.fs.File) !void {
    var tree = TreeDefault.init(allocator);
    defer tree.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        try tree.insert(@intCast(i));
    }

    var t = try std.time.Timer.start();
    i = 0;
    while (i < n) : (i += 1) {
        tree.delete(@intCast(i));
    }
    const ns = t.read();

    // After deleting all, no nodes remain; report memory 0.
    try printCsv(file, "delete,{d},{d},0\n", .{ n, ns });
}

fn profileSelect(allocator: std.mem.Allocator, n: usize, file: *std.fs.File) !void {
    var tree = TreeDefault.init(allocator);
    defer tree.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        try tree.insert(@intCast(i));
    }

    var t = try std.time.Timer.start();
    i = 0;
    while (i < n) : (i += 1) {
        _ = tree.select(i);
    }
    const ns = t.read();

    try printCsv(file, "select,{d},{d},{d}\n", .{ n, ns, n * nodeSizeBytes() });
}

fn profileSuccessor(allocator: std.mem.Allocator, n: usize, file: *std.fs.File) !void {
    var tree = TreeDefault.init(allocator);
    defer tree.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        try tree.insert(@intCast(i));
    }

    var t = try std.time.Timer.start();
    i = 0;
    while (i < n) : (i += 1) {
        _ = tree.successor(@intCast(i));
    }
    const ns = t.read();

    try printCsv(file, "successor,{d},{d},{d}\n", .{ n, ns, n * nodeSizeBytes() });
}
