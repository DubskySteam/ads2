const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const Tree = ost.OrderStatisticTree(i32, cmpI32);

fn makeTree(allocator: std.mem.Allocator, values: []const i32) !Tree {
    var tree = Tree.init(allocator);
    errdefer tree.deinit();

    for (values) |v| {
        try tree.insert(v);
    }
    return tree;
}

test "empty tree basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tree = Tree.init(gpa.allocator());
    defer tree.deinit();

    try std.testing.expect(tree.isEmpty());
    try std.testing.expect(tree.search(42) == false);
    try std.testing.expect(tree.min() == null);
    try std.testing.expect(tree.max() == null);
    try std.testing.expect(tree.predecessor(10) == null);
    try std.testing.expect(tree.successor(10) == null);
}

test "insert and search" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(gpa.allocator(), &values);
    defer tree.deinit();

    // All inserted values must be found
    for (values) |v| {
        try std.testing.expect(tree.search(v));
    }

    // Some non-existing values
    try std.testing.expect(!tree.search(0));
    try std.testing.expect(!tree.search(11));
}

test "min, max, and in-order traversal indices" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Same dataset as the demo
    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(gpa.allocator(), &values);
    defer tree.deinit();

    const min_res = tree.min() orelse return error.TestExpectedResult;
    const max_res = tree.max() orelse return error.TestExpectedResult;

    try std.testing.expectEqual(@as(i32, 1), min_res.data);
    try std.testing.expectEqual(@as(usize, 0), min_res.index);

    try std.testing.expectEqual(@as(i32, 10), max_res.data);
    try std.testing.expectEqual(@as(usize, 9), max_res.index);

    // Walk the tree in order using successor and check (index, value) pairs.
    var expected_val: i32 = 1;
    var expected_idx: usize = 0;

    var current_opt = tree.min();
    while (current_opt) |current| {
        try std.testing.expectEqual(expected_val, current.data);
        try std.testing.expectEqual(expected_idx, current.index);

        expected_val += 1;
        expected_idx += 1;
        current_opt = tree.successor(current.data);
    }

    // We inserted exactly 10 distinct values.
    try std.testing.expectEqual(@as(i32, 11), expected_val);
    try std.testing.expectEqual(@as(usize, 10), expected_idx);
}

test "predecessor and successor (strict neighbors)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(gpa.allocator(), &values);
    defer tree.deinit();

    // For smallest element: no predecessor, successor is 2
    try std.testing.expect(tree.predecessor(1) == null);
    const succ1 = tree.successor(1) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 2), succ1.data);
    try std.testing.expectEqual(@as(usize, 1), succ1.index);

    // For largest element: predecessor is 9, no successor
    const pred10 = tree.predecessor(10) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 9), pred10.data);
    try std.testing.expectEqual(@as(usize, 8), pred10.index);
    try std.testing.expect(tree.successor(10) == null);

    // Middle elements: neighbors as expected
    const pred5 = tree.predecessor(5) orelse return error.TestExpectedResult;
    const succ5 = tree.successor(5) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 4), pred5.data);
    try std.testing.expectEqual(@as(i32, 6), succ5.data);
}

test "duplicates affect ranks correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 1, then three 2s, then 3
    const values = [_]i32{ 1, 2, 2, 2, 3 };
    var tree = try makeTree(gpa.allocator(), &values);
    defer tree.deinit();

    const min_res = tree.min() orelse return error.TestExpectedResult;
    const max_res = tree.max() orelse return error.TestExpectedResult;

    // In-order multiset is [1,2,2,2,3]
    try std.testing.expectEqual(@as(i32, 1), min_res.data);
    try std.testing.expectEqual(@as(usize, 0), min_res.index);

    try std.testing.expectEqual(@as(i32, 3), max_res.data);
    try std.testing.expectEqual(@as(usize, 4), max_res.index);

    // Predecessor of 3 should be 2, whose first index is 1.
    const pred3 = tree.predecessor(3) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 2), pred3.data);
    try std.testing.expectEqual(@as(usize, 1), pred3.index);
}
