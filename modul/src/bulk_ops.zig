//! Bulk Operations for Red-Black Tree
//!
//! This module provides efficient batch operations for Red-Black Trees:
//! - bulkInsert: Insert multiple values at once
//! - bulkDelete: Delete multiple values at once
//! - rangeQuery: Extract all values in a given range [low, high]
//!
//! Usage:
//!   const bulk = @import("bulk_ops");
//!   try bulk.bulkInsert(i32, &tree, &[_]i32{1, 2, 3});
//!   const range = try bulk.rangeQuery(i32, &tree, allocator, 10, 20);

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Insert multiple values into the tree in one batch
/// 
/// Complexity: O(k log n) where k = number of values to insert
/// 
/// Parameters:
///   - T: The type of values stored in the tree
///   - tree: Pointer to the tree instance
///   - values: Slice of values to insert
/// 
/// Note: Duplicates are silently ignored (set semantics)
pub fn bulkInsert(comptime T: type, tree: anytype, values: []const T) !void {
    for (values) |val| {
        try tree.insert(val);
    }
}

/// Delete multiple values from the tree in one batch
/// 
/// Complexity: O(k log n) where k = number of values to delete
/// 
/// Parameters:
///   - T: The type of values stored in the tree
///   - tree: Pointer to the tree instance
///   - values: Slice of values to delete
/// 
/// Note: Non-existent values are silently skipped
pub fn bulkDelete(comptime T: type, tree: anytype, values: []const T) void {
    _ = T;
    for (values) |val| {
        tree.delete(val);
    }
}

/// Extract all values in the range [low, high] (inclusive on both ends)
/// 
/// Complexity: O(log n + m) where m = number of values in range
/// 
/// Parameters:
///   - T: The type of values stored in the tree
///   - tree: Pointer to the tree instance
///   - allocator: Allocator for the result array
///   - low: Lower bound (inclusive)
///   - high: Upper bound (inclusive)
/// 
/// Returns:
///   Owned slice containing all values in [low, high] in sorted order.
///   Caller must free the returned slice.
/// 
/// Example:
///   const result = try rangeQuery(i32, &tree, allocator, 10, 20);
///   defer allocator.free(result);
pub fn rangeQuery(comptime T: type, tree: anytype, allocator: Allocator, low: T, high: T) ![]T {
    // Find start index: smallest value >= low
    const start_result = tree.successor(low);
    if (start_result[0] == -1) {
        // No values >= low → empty range
        return try allocator.alloc(T, 0);
    }

    const start_index: usize = @intCast(start_result[0]);

    // Collect all values in range [low, high]
    var result = std.ArrayList(T).init(allocator);
    errdefer result.deinit();

    var i = start_index;
    while (i < tree.size()) : (i += 1) {
        const val = tree.getAt(i) orelse break;

        // Stop when we exceed high bound
        if (val > high) break;

        // Only include values >= low (successor guarantees this, but be safe)
        if (val >= low) {
            try result.append(val);
        }
    }

    return try result.toOwnedSlice();
}

/// Count how many values exist in the range [low, high] (inclusive)
/// 
/// Complexity: O(log n + m) where m = number of values in range
/// 
/// Parameters:
///   - T: The type of values stored in the tree
///   - tree: Pointer to the tree instance
///   - low: Lower bound (inclusive)
///   - high: Upper bound (inclusive)
/// 
/// Returns:
///   Number of values in [low, high]
/// 
/// Note: This is more efficient than rangeQuery if you only need the count
pub fn rangeCount(comptime T: type, tree: anytype, low: T, high: T) usize {
    _ = T;

    // Find start: smallest value >= low
    const start_result = tree.successor(low);
    if (start_result[0] == -1) return 0;

    const start_index: usize = @intCast(start_result[0]);

    // Count values until we exceed high
    var count: usize = 0;
    var i = start_index;

    while (i < tree.size()) : (i += 1) {
        const val = tree.getAt(i) orelse break;
        if (val > high) break;
        if (val >= low) count += 1;
    }

    return count;
}

/// Delete all values in the range [low, high] (inclusive)
/// 
/// Complexity: O(log n + m log n) where m = number of values in range
/// 
/// Parameters:
///   - T: The type of values stored in the tree
///   - tree: Pointer to the tree instance
///   - allocator: Temporary allocator for collecting values
///   - low: Lower bound (inclusive)
///   - high: Upper bound (inclusive)
/// 
/// Returns:
///   Number of values deleted
/// 
/// Note: This first collects all values in range, then deletes them.
///       This avoids iterator invalidation issues.
pub fn rangeDelete(comptime T: type, tree: anytype, allocator: Allocator, low: T, high: T) !usize {
    // First collect all values in range
    const values = try rangeQuery(T, tree, allocator, low, high);
    defer allocator.free(values);

    // Then delete them all
    for (values) |val| {
        tree.delete(val);
    }

    return values.len;
}
