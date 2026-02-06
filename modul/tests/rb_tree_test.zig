//! Comprehensive test suite for rb_tree.zig
//! Tests both default configuration and optimized (pooled+stats) variant.

const std = @import("std");
const testing = std.testing;
const rb = @import("rb_tree");

// =============================================================================
// Test Configuration: Two Variants
// =============================================================================

/// Default configuration: no pooling, no stats, minmax cache enabled
const TreeDefault = rb.Tree(i32, .{
    .enable_pool = false,
    .enable_stats = false,
    .enable_minmax_cache = true,
});

/// Optimized configuration: pooling + stats enabled
const TreePooled = rb.Tree(i32, .{
    .enable_pool = true,
    .max_pool_size = 1000,
    .enable_stats = true,
    .enable_minmax_cache = true,
});

// =============================================================================
// Top-Level Test Entry Points
// =============================================================================

test "RBTree suite (default config)" {
    try runFullTestSuite(TreeDefault);
}

test "RBTree suite (pooled+stats config)" {
    try runFullTestSuite(TreePooled);
}

// =============================================================================
// Main Test Suite Runner
// =============================================================================

/// Runs all test sections for a given Tree configuration
fn runFullTestSuite(comptime TreeType: type) !void {
    try testEmptyTree(TreeType);
    try testBasicOperations(TreeType);
    try testOrderStatistics(TreeType);
    try testPredecessorSuccessor(TreeType);
    try testDeletion(TreeType);
    try testInsertAt(TreeType);
    try testEdgeCases(TreeType);
    try testLargeDataset(TreeType);
    try testPooling(TreeType);
}

// =============================================================================
// Section 1: Empty Tree Tests
// =============================================================================

/// Tests behavior of an empty tree
fn testEmptyTree(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Size and emptiness
    try testing.expect(tree.isEmpty());
    try testing.expectEqual(@as(usize, 0), tree.size());

    // Min/Max should be null
    try testing.expectEqual(@as(?i32, null), tree.min());
    try testing.expectEqual(@as(?i32, null), tree.max());

    // getAt on empty tree
    try testing.expectEqual(@as(?i32, null), tree.getAt(0));

    // Search on empty tree
    try testing.expect(!tree.search(42));

    // indexOf on empty tree
    try testing.expectEqual(@as(i64, -1), tree.indexOf(42));

    // predecessor/successor on empty tree (spec: should return -1, -1)
    {
        const pred = tree.predecessor(10);
        try testing.expectEqual(@as(i64, -1), pred[0]);
        try testing.expectEqual(@as(i32, -1), pred[1]);
    }
    {
        const succ = tree.successor(10);
        try testing.expectEqual(@as(i64, -1), succ[0]);
        try testing.expectEqual(@as(i32, -1), succ[1]);
    }
}

// =============================================================================
// Section 2: Basic Operations (Insert, Search, Delete)
// =============================================================================

/// Tests insert, search, size, isEmpty, min, max
fn testBasicOperations(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert values: 10, 5, 15, 3, 7, 12, 20
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);
    try tree.insert(12);
    try tree.insert(20);

    // Size and emptiness
    try testing.expectEqual(@as(usize, 7), tree.size());
    try testing.expect(!tree.isEmpty());

    // Search (existing)
    try testing.expect(tree.search(10));
    try testing.expect(tree.search(3));
    try testing.expect(tree.search(20));

    // Search (non-existing)
    try testing.expect(!tree.search(999));
    try testing.expect(!tree.search(0));

    // Min/Max
    try testing.expectEqual(@as(?i32, 3), tree.min());
    try testing.expectEqual(@as(?i32, 20), tree.max());

    // Duplicate insert (should be ignored, size unchanged)
    try tree.insert(10);
    try testing.expectEqual(@as(usize, 7), tree.size());
}

// =============================================================================
// Section 3: Order Statistics (getAt, indexOf)
// =============================================================================

/// Tests index-based access and rank queries
fn testOrderStatistics(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert: 10, 5, 15, 3, 7, 12, 20
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);
    try tree.insert(12);
    try tree.insert(20);

    // Expected sorted order: [3, 5, 7, 10, 12, 15, 20]

    // getAt: verify all indices
    try testing.expectEqual(@as(?i32, 3), tree.getAt(0));
    try testing.expectEqual(@as(?i32, 5), tree.getAt(1));
    try testing.expectEqual(@as(?i32, 7), tree.getAt(2));
    try testing.expectEqual(@as(?i32, 10), tree.getAt(3));
    try testing.expectEqual(@as(?i32, 12), tree.getAt(4));
    try testing.expectEqual(@as(?i32, 15), tree.getAt(5));
    try testing.expectEqual(@as(?i32, 20), tree.getAt(6));

    // getAt: out of bounds
    try testing.expectEqual(@as(?i32, null), tree.getAt(7));
    try testing.expectEqual(@as(?i32, null), tree.getAt(100));

    // indexOf: existing elements
    try testing.expectEqual(@as(i64, 0), tree.indexOf(3));
    try testing.expectEqual(@as(i64, 3), tree.indexOf(10));
    try testing.expectEqual(@as(i64, 6), tree.indexOf(20));

    // indexOf: non-existing element
    try testing.expectEqual(@as(i64, -1), tree.indexOf(999));
    try testing.expectEqual(@as(i64, -1), tree.indexOf(0));
}

// =============================================================================
// Section 4: Predecessor and Successor (Spec-Compliant)
// =============================================================================

/// Tests predecessor and successor (must return -1, -1 if not found)
fn testPredecessorSuccessor(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert: 5, 10, 15, 20
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(20);

    // --- Predecessor Tests ---

    // predecessor(12) → should find 10 (largest <= 12)
    {
        const pred = tree.predecessor(12);
        try testing.expectEqual(@as(i32, 10), pred[1]);
        try testing.expect(pred[0] >= 0);
    }

    // predecessor(5) → should find 5 (semantics "<=")
    {
        const pred = tree.predecessor(5);
        try testing.expectEqual(@as(i32, 5), pred[1]);
    }

    // predecessor(20) → should find 20
    {
        const pred = tree.predecessor(20);
        try testing.expectEqual(@as(i32, 20), pred[1]);
    }

    // predecessor(3) → nothing <= 3, should return (-1, -1)
    {
        const pred = tree.predecessor(3);
        try testing.expectEqual(@as(i64, -1), pred[0]);
        try testing.expectEqual(@as(i32, -1), pred[1]);
    }

    // predecessor(25) → should find 20 (largest in tree)
    {
        const pred = tree.predecessor(25);
        try testing.expectEqual(@as(i32, 20), pred[1]);
    }

    // --- Successor Tests ---

    // successor(12) → should find 15 (smallest >= 12)
    {
        const succ = tree.successor(12);
        try testing.expectEqual(@as(i32, 15), succ[1]);
    }

    // successor(5) → should find 5 (semantics ">=")
    {
        const succ = tree.successor(5);
        try testing.expectEqual(@as(i32, 5), succ[1]);
    }

    // successor(20) → should find 20
    {
        const succ = tree.successor(20);
        try testing.expectEqual(@as(i32, 20), succ[1]);
    }

    // successor(25) → nothing >= 25, should return (-1, -1)
    {
        const succ = tree.successor(25);
        try testing.expectEqual(@as(i64, -1), succ[0]);
        try testing.expectEqual(@as(i32, -1), succ[1]);
    }

    // successor(3) → should find 5 (smallest in tree)
    {
        const succ = tree.successor(3);
        try testing.expectEqual(@as(i32, 5), succ[1]);
    }
}

// =============================================================================
// Section 5: Deletion (delete, deleteAt)
// =============================================================================

/// Tests value-based and index-based deletion
fn testDeletion(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert: 3, 5, 7, 10, 12, 15, 20
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);
    try tree.insert(12);
    try tree.insert(20);

    // delete(7)
    tree.delete(7);
    try testing.expect(!tree.search(7));
    try testing.expectEqual(@as(usize, 6), tree.size());

    // Current sorted: [3, 5, 10, 12, 15, 20]

    // deleteAt(2) → should delete 10
    const deleted = tree.deleteAt(2);
    try testing.expectEqual(@as(?i32, 10), deleted);
    try testing.expect(!tree.search(10));
    try testing.expectEqual(@as(usize, 5), tree.size());

    // Current sorted: [3, 5, 12, 15, 20]

    // deleteAt: out of bounds
    const invalid = tree.deleteAt(100);
    try testing.expectEqual(@as(?i32, null), invalid);

    // delete: non-existing element (no-op)
    tree.delete(999);
    try testing.expectEqual(@as(usize, 5), tree.size());
}

// =============================================================================
// Section 6: insertAt (Order-Preserving Insert)
// =============================================================================

/// Tests insertAt: must maintain sorted order
fn testInsertAt(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert: 3, 5, 12, 15, 20
    try tree.insert(5);
    try tree.insert(3);
    try tree.insert(12);
    try tree.insert(15);
    try tree.insert(20);

    // Sorted: [3, 5, 12, 15, 20]

    // insertAt(2, 10) → should fit between 5 and 12
    try tree.insertAt(2, 10);
    try testing.expect(tree.search(10));
    try testing.expectEqual(@as(?i32, 10), tree.getAt(2));
    try testing.expectEqual(@as(usize, 6), tree.size());

    // Sorted now: [3, 5, 10, 12, 15, 20]

    // insertAt(3, 1) → would violate order (1 is not between 10 and 12)
    try testing.expectError(error.InvalidPosition, tree.insertAt(3, 1));

    // insertAt: out of bounds
    try testing.expectError(error.IndexOutOfBounds, tree.insertAt(100, 99));

    // insertAt on empty tree
    var empty = TreeType.init(testing.allocator);
    defer empty.deinit();
    try empty.insertAt(0, 42);
    try testing.expect(empty.search(42));
}

// =============================================================================
// Section 7: Edge Cases
// =============================================================================

/// Tests single-element tree and boundary conditions
fn testEdgeCases(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Single element
    try tree.insert(42);
    try testing.expectEqual(@as(usize, 1), tree.size());
    try testing.expectEqual(@as(?i32, 42), tree.min());
    try testing.expectEqual(@as(?i32, 42), tree.max());
    try testing.expectEqual(@as(?i32, 42), tree.getAt(0));
    try testing.expectEqual(@as(i64, 0), tree.indexOf(42));

    // predecessor/successor of the only element
    {
        const pred = tree.predecessor(42);
        try testing.expectEqual(@as(i32, 42), pred[1]);
    }
    {
        const succ = tree.successor(42);
        try testing.expectEqual(@as(i32, 42), succ[1]);
    }

    // Delete the only element
    tree.delete(42);
    try testing.expect(tree.isEmpty());
    try testing.expectEqual(@as(?i32, null), tree.min());
    try testing.expectEqual(@as(?i32, null), tree.max());
}

// =============================================================================
// Section 8: Large Dataset Sanity Check
// =============================================================================

/// Tests tree with 1000 elements
fn testLargeDataset(comptime TreeType: type) !void {
    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    const n: i32 = 1000;
    var i: i32 = 0;

    // Insert 0..999
    while (i < n) : (i += 1) {
        try tree.insert(i);
    }

    // Size check
    try testing.expectEqual(@as(usize, @intCast(n)), tree.size());

    // Min/Max
    try testing.expectEqual(@as(?i32, 0), tree.min());
    try testing.expectEqual(@as(?i32, n - 1), tree.max());

    // Spot checks
    try testing.expect(tree.search(0));
    try testing.expect(tree.search(500));
    try testing.expect(tree.search(999));
    try testing.expect(!tree.search(1001));

    // Order checks
    try testing.expectEqual(@as(?i32, 0), tree.getAt(0));
    try testing.expectEqual(@as(?i32, 500), tree.getAt(500));
    try testing.expectEqual(@as(?i32, 999), tree.getAt(999));

    // Predecessor/Successor spot checks
    {
        const pred = tree.predecessor(500);
        try testing.expectEqual(@as(i32, 500), pred[1]);
    }
    {
        const succ = tree.successor(500);
        try testing.expectEqual(@as(i32, 500), succ[1]);
    }
}

// =============================================================================
// Section 9: Pooling Tests (Stats-Enabled Trees Only)
// =============================================================================

/// Tests node pooling behavior (only runs if stats are enabled)
fn testPooling(comptime TreeType: type) !void {
    // Only run if TreeType has stats enabled (compile-time check)
    const has_stats = comptime blk: {
        const type_info = @typeInfo(TreeType);
        if (type_info != .@"struct") break :blk false;

        // Check if getStats exists
        if (!@hasDecl(TreeType, "getStats")) break :blk false;

        // Check if Stats type has allocations field
        // We need to look at the actual Stats type in the struct
        for (type_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "stats")) {
                const stats_type = field.type;
                const stats_info = @typeInfo(stats_type);
                if (stats_info == .@"struct") {
                    break :blk @hasField(stats_type, "allocations");
                }
            }
        }
        break :blk false;
    };

    if (!has_stats) return;

    var tree = TreeType.init(testing.allocator);
    defer tree.deinit();

    // Insert 100 elements
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try tree.insert(i);
    }

    var st = tree.getStats();
    // Should have allocated at least 100 nodes
    try testing.expect(st.allocations >= 100);

    // Delete all 100 → nodes should go into free list (up to max_pool_size)
    i = 0;
    while (i < 100) : (i += 1) {
        tree.delete(i);
    }

    st = tree.getStats();
    // free_list_size should be min(100, max_pool_size)
    const expected_pool_size = @min(@as(usize, 100), 1000);
    try testing.expectEqual(expected_pool_size, st.free_list_size);

    // Re-insert 50 elements → should reuse from pool
    i = 0;
    while (i < 50) : (i += 1) {
        try tree.insert(i + 10_000); // different values to avoid duplicates
    }

    const st2 = tree.getStats();
    // Should have at least min(50, free_list_size) reuses
    try testing.expect(st2.reuses >= @min(@as(usize, 50), expected_pool_size));

    // Verify reuses > 0 (proof that pooling works)
    try testing.expect(st2.reuses > 0);
}

// =============================================================================
// Compile-Time Helper: Check if TreeType has stats enabled
// =============================================================================

fn hasStats(comptime TreeType: type) bool {
    // Check if getStats method exists and returns a struct with "allocations" field
    if (!@hasDecl(TreeType, "getStats")) return false;

    // Create a dummy instance to get the return type
    const dummy_alloc = testing.allocator;
    const dummy_tree = TreeType.init(dummy_alloc);
    const StatsType = @TypeOf(dummy_tree.getStats());

    return @hasField(StatsType, "allocations");
}
