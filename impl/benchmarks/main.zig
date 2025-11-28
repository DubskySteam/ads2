const std = @import("std");
const ost_lib = @import("ost");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // New IO API (0.15.x)
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Benchmark running...\n", .{});

    const OST = ost_lib.OrderStatisticTree(i32, std.math.order);
    var tree = OST.init(allocator);
    defer tree.deinit();

    try tree.insert(42);
    try stdout.print("Benchmark initialized successfully.\n", .{});

    try stdout.flush(); // IMPORTANT: flush buffered writer
}
