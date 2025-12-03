const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

// Two configs: default and compact_sizes = true
const TreeDefault = ost.OrderStatisticTree(i32, cmpI32, .{});
const TreeCompact = ost.OrderStatisticTree(i32, cmpI32, .{
    .compact_sizes = true,
});

// Generic helpers so we can run the same logical tests for both configs.

fn makeTree(comptime TreeType: type, allocator: std.mem.Allocator, values: []const i32) !TreeType {
    var tree = TreeType.init(allocator);
    errdefer tree.deinit();

    for (values) |v| {
        try tree.insert(v);
    }
    return tree;
}

fn test_empty_tree_basics(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tree = TreeType.init(gpa.allocator());
    defer tree.deinit();

    try std.testing.expect(tree.isEmpty());
    try std.testing.expect(tree.search(42) == false);
    try std.testing.expect(tree.min() == null);
    try std.testing.expect(tree.max() == null);
    try std.testing.expect(tree.predecessor(10) == null);
    try std.testing.expect(tree.successor(10) == null);
}

fn test_insert_and_search(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
    defer tree.deinit();

    // All inserted values must be found
    for (values) |v| {
        try std.testing.expect(tree.search(v));
    }

    // Some non-existing values
    try std.testing.expect(!tree.search(0));
    try std.testing.expect(!tree.search(11));
}

fn test_min_max_and_inorder_indices(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
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

fn test_predecessor_successor_neighbors(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
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

// Check behavior for keys that are not present: predecessor(x) = max < x, successor(x) = min > x.
fn test_predecessor_successor_non_present(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 1, 3, 5, 7, 9 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
    defer tree.deinit();

    // x between 3 and 5
    const pred4 = tree.predecessor(4) orelse return error.TestExpectedResult;
    const succ4 = tree.successor(4) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 3), pred4.data);
    try std.testing.expectEqual(@as(i32, 5), succ4.data);

    // x smaller than min: no predecessor, successor is 1
    try std.testing.expect(tree.predecessor(0) == null);
    const succ0 = tree.successor(0) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 1), succ0.data);

    // x greater than max: predecessor is 9, no successor
    const pred10 = tree.predecessor(10) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 9), pred10.data);
    try std.testing.expect(tree.successor(10) == null);
}

fn test_duplicates_and_ranks(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 1, then three 2s, then 3
    const values = [_]i32{ 1, 2, 2, 2, 3 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
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

// New: test delete behavior, including deleting duplicates.
fn test_delete_operations(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Mix of values to hit different delete cases.
    const values = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
    defer tree.deinit();

    // Delete a leaf (2), a node with one child (10), and a node with two children (5).
    tree.delete(2);
    try std.testing.expect(!tree.search(2));

    tree.delete(10);
    try std.testing.expect(!tree.search(10));

    tree.delete(5);
    try std.testing.expect(!tree.search(5));

    // Remaining elements should still be searchable and in correct range.
    try std.testing.expect(tree.search(1));
    try std.testing.expect(tree.search(3));
    try std.testing.expect(tree.search(4));
    try std.testing.expect(tree.search(6));
    try std.testing.expect(tree.search(7));
    try std.testing.expect(tree.search(8));
    try std.testing.expect(tree.search(9));

    // Now delete everything and ensure tree is empty.
    const remaining = [_]i32{ 1, 3, 4, 6, 7, 8, 9 };
    for (remaining) |v| {
        tree.delete(v);
    }
    try std.testing.expect(tree.isEmpty());
    try std.testing.expect(tree.min() == null);
    try std.testing.expect(tree.max() == null);
}

fn test_delete_with_duplicates(comptime TreeType: type) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const values = [_]i32{ 1, 2, 2, 2, 3 };
    var tree = try makeTree(TreeType, gpa.allocator(), &values);
    defer tree.deinit();

    // Delete 2 twice: node should still exist (count drops from 3 to 1).
    tree.delete(2);
    tree.delete(2);
    try std.testing.expect(tree.search(2));

    // Max should still be 3 at index 4 (multiset [1,2,3]).
    const max_res = tree.max() orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 3), max_res.data);
    try std.testing.expectEqual(@as(usize, 2), max_res.index);

    // Final delete removes the node entirely.
    tree.delete(2);
    try std.testing.expect(!tree.search(2));
    const pred3 = tree.predecessor(3) orelse return error.TestExpectedResult;
    try std.testing.expectEqual(@as(i32, 1), pred3.data);
}

test "empty tree basics (default config)" {
    try test_empty_tree_basics(TreeDefault);
}

test "empty tree basics (compact_sizes=true)" {
    try test_empty_tree_basics(TreeCompact);
}

test "insert and search (both configs)" {
    try test_insert_and_search(TreeDefault);
    try test_insert_and_search(TreeCompact);
}

test "min, max, and in-order traversal indices (both configs)" {
    try test_min_max_and_inorder_indices(TreeDefault);
    try test_min_max_and_inorder_indices(TreeCompact);
}

test "predecessor and successor (strict neighbors, both configs)" {
    try test_predecessor_successor_neighbors(TreeDefault);
    try test_predecessor_successor_neighbors(TreeCompact);
}

test "predecessor and successor on non-present keys (both configs)" {
    try test_predecessor_successor_non_present(TreeDefault);
    try test_predecessor_successor_non_present(TreeCompact);
}

test "duplicates affect ranks and deletion correctly (both configs)" {
    try test_duplicates_and_ranks(TreeDefault);
    try test_duplicates_and_ranks(TreeCompact);
    try test_delete_with_duplicates(TreeDefault);
    try test_delete_with_duplicates(TreeCompact);
}

test "delete operations on various node shapes (both configs)" {
    try test_delete_operations(TreeDefault);
    try test_delete_operations(TreeCompact);
}
