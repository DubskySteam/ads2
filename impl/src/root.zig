const std = @import("std");
const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const node_mod = @import("node.zig");

pub const OrderStatisticTreeConfig = struct {
    const AllocationMode = enum {
        general, // use upstream allocator directly
        arena, // use internal ArenaAllocator
    };

    use_freelist: bool = true,
    allocation_mode: AllocationMode = .general,
};

pub fn OrderStatisticTree(
    comptime T: type,
    comptime compareFn: fn (a: T, b: T) std.math.Order,
    comptime cfg: OrderStatisticTreeConfig,
) type {
    return struct {
        const Self = @This();
        pub const Node = node_mod.Node(T);
        pub const NodeResult = node_mod.NodeResult(T);

        const AllocState = switch (cfg.allocation_mode) {
            .general => struct {
                const SelfAlloc = @This();

                upstream: Allocator,

                fn init(upstream: Allocator) SelfAlloc {
                    return .{ .upstream = upstream };
                }

                fn deinit(self: *SelfAlloc) void {
                    _ = self;
                }

                inline fn alloc(self: *SelfAlloc) !*Node {
                    return try self.upstream.create(Node);
                }

                inline fn free(self: *SelfAlloc, node: *Node) void {
                    self.upstream.destroy(node);
                }
            },
            .arena => struct {
                const SelfAlloc = @This();

                arena: std.heap.ArenaAllocator,

                fn init(upstream: Allocator) SelfAlloc {
                    return .{ .arena = std.heap.ArenaAllocator.init(upstream) };
                }

                fn deinit(self: *SelfAlloc) void {
                    self.arena.deinit();
                }

                inline fn alloc(self: *SelfAlloc) !*Node {
                    return try self.arena.allocator().create(Node);
                }

                inline fn free(self: *SelfAlloc, node: *Node) void {
                    _ = self;
                    _ = node; // per-node free is intentionally a no-op
                }
            },
        };

        root: ?*Node,
        alloc_state: AllocState,
        free_list: ?*Node = null,

        pub fn init(upstream: Allocator) Self {
            return .{
                .root = null,
                .alloc_state = AllocState.init(upstream),
                .free_list = null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root| self.deinitNode(root);

            if (cfg.use_freelist) {
                var n = self.free_list;
                while (n) |node| {
                    const next = node.right;
                    self.alloc_state.free(node);
                    n = next;
                }
                self.free_list = null;
            }

            self.alloc_state.deinit();
        }

        fn deinitNode(self: *Self, node: *Node) void {
            if (node.left) |l| self.deinitNode(l);
            if (node.right) |r| self.deinitNode(r);
            self.alloc_state.free(node);
        }

        inline fn allocNode(self: *Self) !*Node {
            if (cfg.use_freelist) {
                if (self.free_list) |n| {
                    self.free_list = n.right;
                    n.parent = null;
                    n.left = null;
                    n.right = null;
                    return n;
                }
            }
            return try self.alloc_state.alloc();
        }

        inline fn freeNode(self: *Self, node: *Node) void {
            if (cfg.use_freelist) {
                node.parent = null;
                node.left = null;
                node.right = self.free_list;
                self.free_list = node;
            } else {
                self.alloc_state.free(node);
            }
        }

        pub fn insert(self: *Self, data: T) !void {
            var y: ?*Node = null;
            var x = self.root;

            while (x) |node| {
                y = node;
                switch (compareFn(data, node.data)) {
                    .eq => {
                        node.count += 1;
                        self.updatePathSize(node);
                        return;
                    },
                    .lt => x = node.left,
                    .gt => x = node.right,
                }
            }

            const new_node = try self.allocNode();
            new_node.* = Node{
                .data = data,
                .size = 1,
                .count = 1,
                .parent = y,
                .left = null,
                .right = null,
                .color = .Red,
            };

            if (y == null) {
                self.root = new_node;
            } else {
                switch (compareFn(data, y.?.data)) {
                    .lt => y.?.left = new_node,
                    .gt => y.?.right = new_node,
                    .eq => unreachable,
                }
            }
            self.updatePathSize(new_node);
            self.insertFixup(new_node);
        }

        pub fn delete(self: *Self, data: T) void {
            const z = self.findNode(data) orelse return;

            if (z.count > 1) {
                z.count -= 1;
                self.updatePathSize(z);
                return;
            }

            var y = z;
            var y_orig_color = y.color;
            var x: ?*Node = null;
            var x_parent: ?*Node = null;

            if (z.left == null) {
                x = z.right;
                x_parent = z.parent;
                self.transplant(z, z.right);
            } else if (z.right == null) {
                x = z.left;
                x_parent = z.parent;
                self.transplant(z, z.left);
            } else {
                y = minimum(z.right.?);
                y_orig_color = y.color;
                x = y.right;

                if (y.parent == z) {
                    if (x) |xn| xn.parent = y;
                    x_parent = y;
                } else {
                    x_parent = y.parent;
                    self.transplant(y, y.right);
                    y.right = z.right;
                    if (y.right) |yr| yr.parent = y;
                }

                self.transplant(z, y);
                y.left = z.left;
                if (y.left) |yl| yl.parent = y;
                y.color = z.color;
            }

            if (x_parent) |xp| {
                self.updatePathSize(xp);
            } else if (x) |xn| {
                self.updatePathSize(xn);
            }

            if (y_orig_color == .Black) {
                self.deleteFixup(x, x_parent);
            }

            self.freeNode(z);
        }

        pub fn search(self: *Self, data: T) bool {
            return self.findNode(data) != null;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.root == null;
        }

        pub fn min(self: *Self) ?NodeResult {
            const m = minimum(self.root orelse return null);
            return NodeResult{ .index = 0, .data = m.data };
        }

        pub fn max(self: *Self) ?NodeResult {
            const m = maximum(self.root orelse return null);
            const total_size = if (self.root) |r| r.size else 0;
            return NodeResult{ .index = total_size - m.count, .data = m.data };
        }

        pub fn predecessor(self: *Self, data: T) ?NodeResult {
            var current = self.root;
            var last_lt: ?*Node = null;

            while (current) |node| {
                switch (compareFn(data, node.data)) {
                    // data > node.data  => node.data < data: candidate, go right
                    .gt => {
                        last_lt = node;
                        current = node.right;
                    },
                    // data <= node.data => go left, do not update candidate
                    .lt, .eq => current = node.left,
                }
            }

            const target = last_lt orelse return null;
            return NodeResult{ .index = self.getRank(target), .data = target.data };
        }

        pub fn successor(self: *Self, data: T) ?NodeResult {
            var current = self.root;
            var last_gt: ?*Node = null;

            while (current) |node| {
                switch (compareFn(data, node.data)) {
                    // data < node.data  => node.data > data: candidate, go left
                    .lt => {
                        last_gt = node;
                        current = node.left;
                    },
                    // data >= node.data => go right, do not update candidate
                    .gt, .eq => current = node.right,
                }
            }

            const target = last_gt orelse return null;
            return NodeResult{ .index = self.getRank(target), .data = target.data };
        }

        fn sizeOf(node: ?*Node) usize {
            return if (node) |n| n.size else 0;
        }

        fn updateSize(self: *Self, node: *Node) void {
            _ = self;
            node.size = sizeOf(node.left) + sizeOf(node.right) + node.count;
        }

        fn updatePathSize(self: *Self, start_node: *Node) void {
            var curr: ?*Node = start_node;
            while (curr) |node| {
                self.updateSize(node);
                curr = node.parent;
            }
        }

        fn findNode(self: *Self, data: T) ?*Node {
            var current = self.root;
            while (current) |node| {
                switch (compareFn(data, node.data)) {
                    .eq => return node,
                    .lt => current = node.left,
                    .gt => current = node.right,
                }
            }
            return null;
        }

        fn minimum(node: *Node) *Node {
            var curr = node;
            while (curr.left) |l| curr = l;
            return curr;
        }

        fn maximum(node: *Node) *Node {
            var curr = node;
            while (curr.right) |r| curr = r;
            return curr;
        }

        fn getRank(self: *Self, node: *Node) usize {
            _ = self;
            var r = sizeOf(node.left);
            var curr = node;

            while (curr.parent) |parent| {
                if (curr == parent.right) {
                    r += sizeOf(parent.left) + parent.count;
                }
                curr = parent;
            }
            return r;
        }

        fn rotateLeft(self: *Self, x: *Node) void {
            const y = x.right orelse return;
            x.right = y.left;

            if (y.left) |yl| yl.parent = x;

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

            self.updateSize(x);
            self.updateSize(y);
        }

        fn rotateRight(self: *Self, y: *Node) void {
            const x = y.left orelse return;
            y.left = x.right;

            if (x.right) |xr| xr.parent = y;

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

            self.updateSize(y);
            self.updateSize(x);
        }

        fn insertFixup(self: *Self, start_z: *Node) void {
            var z = start_z;
            while (z.parent != null and z.parent.?.color == .Red) {
                const p = z.parent.?;
                const pp = p.parent.?;

                if (p == pp.left) {
                    const y = pp.right;
                    if (y != null and y.?.color == .Red) {
                        p.color = .Black;
                        y.?.color = .Black;
                        pp.color = .Red;
                        z = pp;
                    } else {
                        if (z == p.right) {
                            z = p;
                            self.rotateLeft(z);
                        }
                        z.parent.?.color = .Black;
                        pp.color = .Red;
                        self.rotateRight(pp);
                    }
                } else {
                    const y = pp.left;
                    if (y != null and y.?.color == .Red) {
                        p.color = .Black;
                        y.?.color = .Black;
                        pp.color = .Red;
                        z = pp;
                    } else {
                        if (z == p.left) {
                            z = p;
                            self.rotateRight(z);
                        }
                        z.parent.?.color = .Black;
                        pp.color = .Red;
                        self.rotateLeft(pp);
                    }
                }
            }
            self.root.?.color = .Black;
        }

        fn transplant(self: *Self, u: *Node, v: ?*Node) void {
            if (u.parent == null) {
                self.root = v;
            } else if (u == u.parent.?.left) {
                u.parent.?.left = v;
            } else {
                u.parent.?.right = v;
            }
            if (v) |vn| vn.parent = u.parent;
        }

        fn deleteFixup(self: *Self, x_in: ?*Node, x_parent_in: ?*Node) void {
            var x = x_in;
            var x_p = x_parent_in;

            while (x != self.root and (x == null or x.?.color == .Black)) {
                if (x == x_p.?.left) {
                    var w = x_p.?.right.?;

                    if (w.color == .Red) {
                        w.color = .Black;
                        x_p.?.color = .Red;
                        self.rotateLeft(x_p.?);
                        w = x_p.?.right.?;
                    }

                    if ((w.left == null or w.left.?.color == .Black) and
                        (w.right == null or w.right.?.color == .Black))
                    {
                        w.color = .Red;
                        x = x_p;
                        x_p = x.?.parent;
                    } else {
                        if (w.right == null or w.right.?.color == .Black) {
                            if (w.left) |wl| wl.color = .Black;
                            w.color = .Red;
                            self.rotateRight(w);
                            w = x_p.?.right.?;
                        }
                        w.color = x_p.?.color;
                        x_p.?.color = .Black;
                        if (w.right) |wr| wr.color = .Black;
                        self.rotateLeft(x_p.?);
                        x = self.root;
                    }
                } else {
                    var w = x_p.?.left.?;

                    if (w.color == .Red) {
                        w.color = .Black;
                        x_p.?.color = .Red;
                        self.rotateRight(x_p.?);
                        w = x_p.?.left.?;
                    }

                    if ((w.right == null or w.right.?.color == .Black) and
                        (w.left == null or w.left.?.color == .Black))
                    {
                        w.color = .Red;
                        x = x_p;
                        x_p = x.?.parent;
                    } else {
                        if (w.left == null or w.left.?.color == .Black) {
                            if (w.right) |wr| wr.color = .Black;
                            w.color = .Red;
                            self.rotateLeft(w);
                            w = x_p.?.left.?;
                        }
                        w.color = x_p.?.color;
                        x_p.?.color = .Black;
                        if (w.left) |wl| wl.color = .Black;
                        self.rotateRight(x_p.?);
                        x = self.root;
                    }
                }
            }
            if (x) |xn| xn.color = .Black;
        }
    };
}
