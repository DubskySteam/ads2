const std = @import("std");
const rb = @import("rb_tree.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = rb.RedBlackTree(i32).init(allocator);
    defer tree.deinit();

    std.debug.print("=== Red-Black Tree Demo ===\n\n", .{});

    // Insert operations
    std.debug.print("Inserting: 10, 5, 15, 3, 7, 12, 20\n", .{});
    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);
    try tree.insert(12);
    try tree.insert(20);

    tree.printTree();
    std.debug.print("Size: {}\n", .{tree.size()});
    std.debug.print("Is empty: {}\n\n", .{tree.isEmpty()});

    // Search operations
    std.debug.print("Search for 7: {}\n", .{tree.search(7)});
    std.debug.print("Search for 99: {}\n", .{tree.search(99)});
    std.debug.print("Index of 12: {}\n\n", .{tree.indexOf(12)});

    // Index-based operations
    std.debug.print("Element at index 0: {?}\n", .{tree.getAt(0)});
    std.debug.print("Element at index 3: {?}\n", .{tree.getAt(3)});
    std.debug.print("Element at index 6: {?}\n\n", .{tree.getAt(6)});

    // Min/Max
    std.debug.print("Min: {?}\n", .{tree.min()});
    std.debug.print("Max: {?}\n\n", .{tree.max()});

    // Predecessor/Successor
    const pred = tree.predecessor(13);
    if (pred[0] != -1) {
        std.debug.print("Predecessor of 13: index={}, value={}\n", .{ pred[0], pred[1] });
    }

    const succ = tree.successor(13);
    if (succ[0] != -1) {
        std.debug.print("Successor of 13: index={}, value={}\n", .{ succ[0], succ[1] });
    }

    // Delete operation
    std.debug.print("Deleting 5...\n", .{});
    tree.delete(5);
    tree.printTree();
    std.debug.print("Size: {}\n\n", .{tree.size()});

    // DeleteAt operation
    std.debug.print("Deleting element at index 2...\n", .{});
    if (tree.deleteAt(2)) |deleted| {
        std.debug.print("Deleted value: {}\n", .{deleted});
    }
    tree.printTree();
    std.debug.print("Size: {}\n\n", .{tree.size()});

    // InsertAt operation
    std.debug.print("Inserting 11 at appropriate position...\n", .{});
    try tree.insert(11);
    tree.printTree();
    std.debug.print("Size: {}\n", .{tree.size()});
}
