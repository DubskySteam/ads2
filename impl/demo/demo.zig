const std = @import("std");
const ost_lib = @import("ost");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    // Access the library via the namespace
    const OST = ost_lib.OrderStatisticTree(i32, std.math.order);
    var tree = OST.init(allocator);
    defer tree.deinit();

    try stdout.print("Demo: Library structure working.\n", .{});
}
