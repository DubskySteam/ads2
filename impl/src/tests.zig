const std = @import("std");
const expect = std.testing.expect;
const Order = std.math.Order;

const OST = @import("ost.zig").OrderStatisticTree;

fn compareI32(a: i32, b: i32) Order {
    return std.math.order(a, b);
}

test "Order Statistic Tree - Full Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Tree = OST(i32, compareI32);
    var tree = Tree.init(allocator);
    defer tree.deinit();

    // Test: Insert & Duplikate
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(10);

    // Test: Structure
    try expect(tree.root.?.size == 4);

    // Test: Min/Max
    try expect(tree.min().?.data == 5);
    try expect(tree.max().?.data == 15);

    // Test: Predecessor
    const p = tree.predecessor(12);
    try expect(p.?.data == 10);
    try expect(p.?.index == 1); // 5(idx0) -> 10(idx1)

    // Test: Delete
    tree.delete(5);
    try expect(tree.min().?.data == 10);
}
