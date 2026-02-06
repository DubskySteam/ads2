//! Red-Black Tree with Order Statistics
//!
//! This module implements a generic Red-Black Tree (self-balancing binary search tree)
//! augmented with size information for O(log n) order statistics operations (getAt/indexOf).
//!
//! Features (configurable via comptime Config):
//! - Node pooling (free-list) to reduce allocation overhead
//! - Statistics tracking (allocations, reuses, deallocations)
//! - Min/Max caching for O(1) access
//!
//! Usage:
//!   const rb = @import("rb_tree");
//!   var tree = rb.Tree(i32, .{ .enable_pool = true }).init(allocator);
//!   defer tree.deinit();
//!   try tree.insert(42);

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Node color for Red-Black Tree balancing
const Color = enum {
    Red,
    Black,
};

/// Configuration options for Tree behavior (comptime)
pub const Config = struct {
    /// If true, enable node pooling via free-list for reuse after deletion
    enable_pool: bool = false,

    /// Maximum nodes kept in the pool (only used if enable_pool = true)
    max_pool_size: usize = 1000,

    /// If true, track allocations/reuses/deallocations via Stats
    enable_stats: bool = false,

    /// If true, keep min/max cached for O(1) access; if false, O(log n) traversal
    enable_minmax_cache: bool = true,
};

/// Main factory: one file, optional optimizations via comptime config value.
///
/// Usage:
///   const RB = @import("rb_tree");
///   var tree = RB.Tree(i32, .{ .enable_pool = true, .enable_stats = true }).init(alloc);
pub fn Tree(comptime T: type, comptime cfg: Config) type {
    return struct {
        const Self = @This();

        /// Tree node with value, color, pointers, and subtree size (for order statistics)
        pub const Node = struct {
            value: T,
            color: Color,
            left: ?*Node,
            right: ?*Node,
            parent: ?*Node,
            size: usize, // Number of nodes in subtree rooted at this node
        };

        /// Statistics for allocation tracking (only if enable_stats = true)
        pub const Stats = if (cfg.enable_stats) struct {
            allocations: usize = 0,
            deallocations: usize = 0,
            reuses: usize = 0,
            free_list_size: usize = 0,
        } else struct {};

        /// Internal state for node pooling (only if enable_pool = true)
        const PoolState = if (cfg.enable_pool) struct {
            free_list: ?*Node = null, // Head of free-list (singly-linked via left pointer)
            free_list_size: usize = 0,
        } else struct {};

        /// Internal state for min/max caching (only if enable_minmax_cache = true)
        const CacheState = if (cfg.enable_minmax_cache) struct {
            min_cache: ?*Node = null,
            max_cache: ?*Node = null,
        } else struct {};

        root: ?*Node = null,
        allocator: Allocator,
        node_count: usize = 0,
        pool: PoolState = .{},
        stats: Stats = .{},
        cache: CacheState = .{},

        /// Initialize an empty tree with the given allocator
        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Free all nodes and reset tree to empty state
        pub fn deinit(self: *Self) void {
            self.destroySubtreeFinal(self.root);
            self.root = null;
            self.node_count = 0;

            if (comptime cfg.enable_pool) {
                self.clearFreeListFinal();
            }

            if (comptime cfg.enable_minmax_cache) {
                self.cache.min_cache = null;
                self.cache.max_cache = null;
            }
        }

        // =============================================================================
        // Public ADT Operations (as per specification)
        // =============================================================================

        /// Insert value x into the tree (set semantics: duplicates ignored)
        /// Complexity: O(log n)
        pub fn insert(self: *Self, x: T) !void {
            // Check if already exists (set semantics)
            if (self.search(x)) return;

            const new_node = try self.allocNode(x);

            // Special case: empty tree
            if (self.root == null) {
                self.root = new_node;
                new_node.color = .Black;
                self.node_count = 1;
                self.maybeUpdateMinMaxCache();
                return;
            }

            // Standard BST insert
            var current = self.root;
            var parent: ?*Node = null;

            while (current != null) {
                parent = current;
                if (x < current.?.value) {
                    current = current.?.left;
                } else if (x > current.?.value) {
                    current = current.?.right;
                } else {
                    // Duplicate (should not happen due to search check, but be safe)
                    self.releaseNode(new_node);
                    return;
                }
            }

            // Link new node
            new_node.parent = parent;
            if (x < parent.?.value) {
                parent.?.left = new_node;
            } else {
                parent.?.right = new_node;
            }

            self.node_count += 1;
            self.updateSizesToRoot(new_node);
            self.insertFixup(new_node); // Restore Red-Black properties
            self.maybeUpdateMinMaxCache();
        }

        /// Delete value x from the tree (no-op if not present)
        /// Complexity: O(log n)
        pub fn delete(self: *Self, x: T) void {
            const node_to_delete = self.findNode(x) orelse return;
            self.deleteNode(node_to_delete);
        }

        /// Check if value x exists in the tree
        /// Complexity: O(log n)
        pub fn search(self: *Self, x: T) bool {
            return self.findNode(x) != null;
        }

        /// Return the index of value x in sorted order, or -1 if not found
        /// Complexity: O(log n)
        pub fn indexOf(self: *Self, x: T) i64 {
            const node = self.findNode(x) orelse return -1;
            return @intCast(self.getRank(node));
        }

        /// Check if tree is empty
        /// Complexity: O(1)
        pub fn isEmpty(self: *Self) bool {
            return self.node_count == 0;
        }

        /// Return number of elements in tree
        /// Complexity: O(1)
        pub fn size(self: *Self) usize {
            return self.node_count;
        }

        /// Return the value at index i in sorted order, or null if out of bounds
        /// Complexity: O(log n)
        pub fn getAt(self: *Self, i: usize) ?T {
            if (i >= self.node_count) return null;
            const r = self.root orelse return null;
            return self.selectNode(r, i).value;
        }

        /// Delete and return the value at index i, or null if out of bounds
        /// Complexity: O(log n)
        pub fn deleteAt(self: *Self, i: usize) ?T {
            if (i >= self.node_count) return null;
            const r = self.root orelse return null;
            const node = self.selectNode(r, i);
            const value = node.value;
            self.deleteNode(node);
            return value;
        }

        /// Insert x at index i, but only if it maintains sorted order
        /// Returns error if x would violate ordering at position i
        /// Complexity: O(log n)
        pub fn insertAt(self: *Self, i: usize, x: T) !void {
            if (i > self.node_count) return error.IndexOutOfBounds;

            // Special case: empty tree
            if (self.node_count == 0) {
                if (i != 0) return error.IndexOutOfBounds;
                try self.insert(x);
                return;
            }

            // Check if x fits at position i in sorted order
            if (i > 0) {
                const prev = self.getAt(i - 1) orelse return error.InvalidState;
                if (x <= prev) return error.InvalidPosition;
            }
            if (i < self.node_count) {
                const next = self.getAt(i) orelse return error.InvalidState;
                if (x >= next) return error.InvalidPosition;
            }

            try self.insert(x);
        }

        /// Find largest value <= z (with "<=" semantics) and return (index, value).
        /// Returns (-1, -1) if no such value exists.
        /// Complexity: O(log n)
        pub fn predecessor(self: *Self, z: T) struct { i64, T } {
            var current = self.root;
            var result: ?*Node = null;

            while (current) |node| {
                if (node.value <= z) {
                    result = node;
                    current = node.right; // Continue search for larger predecessor
                } else {
                    current = node.left;
                }
            }

            if (result) |r| {
                return .{ @intCast(self.getRank(r)), r.value };
            }
            return .{ -1, -1 };
        }

        /// Find smallest value >= z (with ">=" semantics) and return (index, value).
        /// Returns (-1, -1) if no such value exists.
        /// Complexity: O(log n)
        pub fn successor(self: *Self, z: T) struct { i64, T } {
            var current = self.root;
            var result: ?*Node = null;

            while (current) |node| {
                if (node.value >= z) {
                    result = node;
                    current = node.left; // Continue search for smaller successor
                } else {
                    current = node.right;
                }
            }

            if (result) |r| {
                return .{ @intCast(self.getRank(r)), r.value };
            }
            return .{ -1, -1 };
        }

        /// Return minimum value in tree, or null if empty
        /// Complexity: O(1) if cache enabled, O(log n) otherwise
        pub fn min(self: *Self) ?T {
            if (self.root == null) return null;

            if (comptime cfg.enable_minmax_cache) {
                if (self.cache.min_cache) |n| return n.value;
                return null;
            } else {
                var cur = self.root.?;
                while (cur.left) |l| cur = l;
                return cur.value;
            }
        }

        /// Return maximum value in tree, or null if empty
        /// Complexity: O(1) if cache enabled, O(log n) otherwise
        pub fn max(self: *Self) ?T {
            if (self.root == null) return null;

            if (comptime cfg.enable_minmax_cache) {
                if (self.cache.max_cache) |n| return n.value;
                return null;
            } else {
                var cur = self.root.?;
                while (cur.right) |r| cur = r;
                return cur.value;
            }
        }

        /// Get statistics (allocations, reuses, etc.) if stats are enabled
        pub fn getStats(self: *Self) Stats {
            return self.stats;
        }

        // =============================================================================
        // Internal: Allocation, Pooling, Stats
        // =============================================================================

        /// Allocate a new node (reuse from pool if available and pooling enabled)
        fn allocNode(self: *Self, value: T) !*Node {
            if (comptime cfg.enable_pool) {
                if (self.pool.free_list) |node| {
                    self.pool.free_list = node.left; // left used as next pointer
                    self.pool.free_list_size -= 1;

                    if (comptime cfg.enable_stats) {
                        self.stats.reuses += 1;
                        self.stats.free_list_size = self.pool.free_list_size;
                    }

                    // Reset node for reuse
                    node.* = .{
                        .value = value,
                        .color = .Red,
                        .left = null,
                        .right = null,
                        .parent = null,
                        .size = 1,
                    };
                    return node;
                }
            }

            // Allocate fresh node
            const node = try self.allocator.create(Node);
            if (comptime cfg.enable_stats) {
                self.stats.allocations += 1;
            }

            node.* = .{
                .value = value,
                .color = .Red,
                .left = null,
                .right = null,
                .parent = null,
                .size = 1,
            };
            return node;
        }

        /// Release a node (add to pool if enabled and not full, otherwise deallocate)
        fn releaseNode(self: *Self, node: *Node) void {
            if (comptime cfg.enable_pool) {
                if (self.pool.free_list_size < cfg.max_pool_size) {
                    // Push onto free list (use left as next)
                    node.left = self.pool.free_list;
                    node.right = null;
                    node.parent = null;
                    node.size = 0;
                    self.pool.free_list = node;
                    self.pool.free_list_size += 1;

                    if (comptime cfg.enable_stats) {
                        self.stats.free_list_size = self.pool.free_list_size;
                    }
                    return;
                }
            }

            // Pool full or pooling disabled → deallocate
            self.allocator.destroy(node);
            if (comptime cfg.enable_stats) {
                self.stats.deallocations += 1;
            }
        }

        /// Recursively destroy a subtree (used during final deinit)
        fn destroySubtreeFinal(self: *Self, node: ?*Node) void {
            if (node) |n| {
                self.destroySubtreeFinal(n.left);
                self.destroySubtreeFinal(n.right);
                self.allocator.destroy(n);
                if (comptime cfg.enable_stats) {
                    self.stats.deallocations += 1;
                }
            }
        }

        /// Clear the free list (used during final deinit)
        fn clearFreeListFinal(self: *Self) void {
            if (!cfg.enable_pool) return;

            var cur = self.pool.free_list;
            while (cur) |n| {
                const next = n.left;
                self.allocator.destroy(n);
                if (comptime cfg.enable_stats) {
                    self.stats.deallocations += 1;
                }
                cur = next;
            }
            self.pool.free_list = null;
            self.pool.free_list_size = 0;
            if (comptime cfg.enable_stats) {
                self.stats.free_list_size = 0;
            }
        }

        // =============================================================================
        // Internal: Basic Helper Functions
        // =============================================================================

        /// Find node with value x, or return null
        fn findNode(self: *Self, x: T) ?*Node {
            var current = self.root;
            while (current) |node| {
                if (x == node.value) return node;
                current = if (x < node.value) node.left else node.right;
            }
            return null;
        }

        /// Select the i-th smallest node (0-indexed) via order statistics
        fn selectNode(self: *Self, node: *Node, i: usize) *Node {
            const left_size = if (node.left) |l| l.size else 0;

            if (i == left_size) {
                return node;
            } else if (i < left_size) {
                return self.selectNode(node.left.?, i);
            } else {
                return self.selectNode(node.right.?, i - left_size - 1);
            }
        }

        /// Get rank (0-indexed position in sorted order) of a node
        fn getRank(self: *Self, node: *Node) usize {
            _ = self;
            var rank: usize = if (node.left) |l| l.size else 0;
            var cur = node;

            // Walk up to root, adding left subtree sizes when coming from right
            while (cur.parent) |p| {
                if (p.right == cur) {
                    rank += 1; // Parent itself
                    if (p.left) |l| rank += l.size;
                }
                cur = p;
            }

            return rank;
        }

        /// Update size field of a single node based on children
        fn updateSize(node: *Node) void {
            const ls = if (node.left) |l| l.size else 0;
            const rs = if (node.right) |r| r.size else 0;
            node.size = 1 + ls + rs;
        }

        /// Update sizes from node up to root
        fn updateSizesToRoot(self: *Self, start: *Node) void {
            _ = self;
            var cur: ?*Node = start;
            while (cur) |n| {
                updateSize(n);
                cur = n.parent;
            }
        }

        /// Update min/max cache (if enabled) by traversing to extremes
        fn maybeUpdateMinMaxCache(self: *Self) void {
            if (!cfg.enable_minmax_cache) return;

            if (self.root == null) {
                self.cache.min_cache = null;
                self.cache.max_cache = null;
                return;
            }

            // Find min (leftmost)
            var cur = self.root.?;
            while (cur.left) |l| cur = l;
            self.cache.min_cache = cur;

            // Find max (rightmost)
            cur = self.root.?;
            while (cur.right) |r| cur = r;
            self.cache.max_cache = cur;
        }

        // =============================================================================
        // Internal: Red-Black Tree Rotations
        // =============================================================================

        /// Left rotation around node x
        fn rotateLeft(self: *Self, x: *Node) void {
            const y = x.right orelse return;

            x.right = y.left;
            if (y.left) |l| l.parent = x;

            y.parent = x.parent;
            if (x.parent == null) {
                self.root = y;
            } else if (x == x.parent.?.left) {
                x.parent.?.left = y;
            } else {
                x.parent.?.right = y;
            }

            y.left = x;
            x.parent = y;

            // Update sizes (x first, then y)
            updateSize(x);
            updateSize(y);
        }

        /// Right rotation around node y
        fn rotateRight(self: *Self, y: *Node) void {
            const x = y.left orelse return;

            y.left = x.right;
            if (x.right) |r| r.parent = y;

            x.parent = y.parent;
            if (y.parent == null) {
                self.root = x;
            } else if (y == y.parent.?.right) {
                y.parent.?.right = x;
            } else {
                y.parent.?.left = x;
            }

            x.right = y;
            y.parent = x;

            // Update sizes (y first, then x)
            updateSize(y);
            updateSize(x);
        }

        // =============================================================================
        // Internal: Red-Black Insert Fixup
        // =============================================================================

        /// Restore Red-Black properties after insert (fixes double-red violations)
        fn insertFixup(self: *Self, z_param: *Node) void {
            var z = z_param;
            while (z.parent != null and z.parent.?.color == .Red) {
                if (z.parent == z.parent.?.parent.?.left) {
                    const y = z.parent.?.parent.?.right; // Uncle

                    if (y != null and y.?.color == .Red) {
                        // Case 1: Uncle is red → recolor
                        z.parent.?.color = .Black;
                        y.?.color = .Black;
                        z.parent.?.parent.?.color = .Red;
                        z = z.parent.?.parent.?;
                    } else {
                        if (z == z.parent.?.right) {
                            // Case 2: z is right child → rotate left
                            z = z.parent.?;
                            self.rotateLeft(z);
                        }
                        // Case 3: z is left child → rotate right
                        z.parent.?.color = .Black;
                        z.parent.?.parent.?.color = .Red;
                        self.rotateRight(z.parent.?.parent.?);
                    }
                } else {
                    // Mirror cases (parent is right child)
                    const y = z.parent.?.parent.?.left;

                    if (y != null and y.?.color == .Red) {
                        z.parent.?.color = .Black;
                        y.?.color = .Black;
                        z.parent.?.parent.?.color = .Red;
                        z = z.parent.?.parent.?;
                    } else {
                        if (z == z.parent.?.left) {
                            z = z.parent.?;
                            self.rotateRight(z);
                        }
                        z.parent.?.color = .Black;
                        z.parent.?.parent.?.color = .Red;
                        self.rotateLeft(z.parent.?.parent.?);
                    }
                }
            }
            self.root.?.color = .Black; // Root is always black
        }

        // =============================================================================
        // Internal: Red-Black Delete
        // =============================================================================

        /// Delete a node and restore Red-Black properties
        fn deleteNode(self: *Self, z: *Node) void {
            var y = z;
            var y_original_color = y.color;
            var x: ?*Node = undefined;
            var x_parent: ?*Node = undefined;

            if (z.left == null) {
                x = z.right;
                x_parent = z.parent;
                self.transplant(z, z.right);
            } else if (z.right == null) {
                x = z.left;
                x_parent = z.parent;
                self.transplant(z, z.left);
            } else {
                // z has two children: find successor (minimum in right subtree)
                y = self.minimum(z.right.?);
                y_original_color = y.color;
                x = y.right;

                if (y.parent == z) {
                    x_parent = y;
                    if (x) |xn| xn.parent = y;
                } else {
                    x_parent = y.parent;
                    self.transplant(y, y.right);
                    y.right = z.right;
                    y.right.?.parent = y;
                }

                self.transplant(z, y);
                y.left = z.left;
                y.left.?.parent = y;
                y.color = z.color;
                updateSize(y);
            }

            self.releaseNode(z); // Use pooling if enabled
            self.node_count -= 1;

            // Update sizes up to root
            if (x_parent) |p| {
                self.updateSizesToRoot(p);
            }

            // Restore Red-Black properties if deleted node was black
            if (y_original_color == .Black) {
                self.deleteFixup(x, x_parent);
            }

            self.maybeUpdateMinMaxCache();
        }

        /// Replace subtree rooted at u with subtree rooted at v
        fn transplant(self: *Self, u: *Node, v: ?*Node) void {
            if (u.parent == null) {
                self.root = v;
            } else if (u == u.parent.?.left) {
                u.parent.?.left = v;
            } else {
                u.parent.?.right = v;
            }
            if (v) |n| {
                n.parent = u.parent;
            }
        }

        /// Find minimum node in subtree rooted at node
        fn minimum(self: *Self, node: *Node) *Node {
            _ = self;
            var cur = node;
            while (cur.left) |l| cur = l;
            return cur;
        }

        /// Restore Red-Black properties after delete (fixes black-height violations)
        fn deleteFixup(self: *Self, x_param: ?*Node, x_parent_param: ?*Node) void {
            var x = x_param;
            var x_parent = x_parent_param;

            while (x != self.root and (x == null or x.?.color == .Black)) {
                if (x_parent == null) break; // Safety check

                if (x == x_parent.?.left) {
                    var w = x_parent.?.right; // Sibling

                    if (w != null and w.?.color == .Red) {
                        // Case 1: Sibling is red
                        w.?.color = .Black;
                        x_parent.?.color = .Red;
                        self.rotateLeft(x_parent.?);
                        w = x_parent.?.right;
                    }

                    const w_black_children = w == null or
                        ((w.?.left == null or w.?.left.?.color == .Black) and
                        (w.?.right == null or w.?.right.?.color == .Black));

                    if (w_black_children) {
                        // Case 2: Sibling is black with black children
                        if (w) |wn| wn.color = .Red;
                        x = x_parent;
                        x_parent = x.?.parent;
                    } else {
                        if (w.?.right == null or w.?.right.?.color == .Black) {
                            // Case 3: Sibling is black, left child is red
                            if (w.?.left) |l| l.color = .Black;
                            w.?.color = .Red;
                            self.rotateRight(w.?);
                            w = x_parent.?.right;
                        }
                        // Case 4: Sibling is black, right child is red
                        w.?.color = x_parent.?.color;
                        x_parent.?.color = .Black;
                        if (w.?.right) |r| r.color = .Black;
                        self.rotateLeft(x_parent.?);
                        x = self.root;
                        break;
                    }
                } else {
                    // Mirror cases (x is right child)
                    var w = x_parent.?.left;

                    if (w != null and w.?.color == .Red) {
                        w.?.color = .Black;
                        x_parent.?.color = .Red;
                        self.rotateRight(x_parent.?);
                        w = x_parent.?.left;
                    }

                    const w_black_children = w == null or
                        ((w.?.right == null or w.?.right.?.color == .Black) and
                        (w.?.left == null or w.?.left.?.color == .Black));

                    if (w_black_children) {
                        if (w) |wn| wn.color = .Red;
                        x = x_parent;
                        x_parent = x.?.parent;
                    } else {
                        if (w.?.left == null or w.?.left.?.color == .Black) {
                            if (w.?.right) |r| r.color = .Black;
                            w.?.color = .Red;
                            self.rotateLeft(w.?);
                            w = x_parent.?.left;
                        }
                        w.?.color = x_parent.?.color;
                        x_parent.?.color = .Black;
                        if (w.?.left) |l| l.color = .Black;
                        self.rotateRight(x_parent.?);
                        x = self.root;
                        break;
                    }
                }
            }
            if (x) |n| {
                n.color = .Black;
            }
        }

        // =============================================================================
        // Debug Helper (optional)
        // =============================================================================

        /// Print tree in sorted order (for debugging)
        pub fn printTree(self: *Self) void {
            std.debug.print("Tree (size={}): ", .{self.node_count});
            self.printInOrder(self.root);
            std.debug.print("\n", .{});
        }

        fn printInOrder(self: *Self, node: ?*Node) void {
            if (node) |n| {
                self.printInOrder(n.left);
                std.debug.print("{} ", .{n.value});
                self.printInOrder(n.right);
            }
        }
    };
}

/// Convenience alias: default config (no pooling, no stats, cache enabled)
pub fn RedBlackTree(comptime T: type) type {
    return Tree(T, .{});
}
