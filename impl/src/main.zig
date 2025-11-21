const std = @import("std");
const OST = @import("ost.zig").OrderStatisticTree;
const NodeResult = @import("node.zig").NodeResult(i32);

fn compareI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const Printer = struct {
    pub fn header() void {
        std.debug.print("\n{s}\n", .{"=" ** 60});
        std.debug.print("| {s:<10} | {s:<10} | {s:<15} | {s:<10} |\n", .{ "Operation", "Input", "Result (Data)", "Index" });
        std.debug.print("{s}\n", .{"-" ** 60});
    }

    pub fn row(op: []const u8, input: ?i32, res: ?NodeResult) void {
        const in_str = if (input) |v| std.fmt.allocPrint(std.heap.page_allocator, "{}", .{v}) catch "-" else "-";
        const data_str = if (res) |r| std.fmt.allocPrint(std.heap.page_allocator, "{}", .{r.data}) catch "-" else "-";
        const idx_str = if (res) |r| std.fmt.allocPrint(std.heap.page_allocator, "{}", .{r.index}) catch "-" else "-";

        std.debug.print("| {s:<10} | {s:<10} | {s:<15} | {s:<10} |\n", .{ op, in_str, data_str, idx_str });
    }

    pub fn divider() void {
        std.debug.print("{s}\n", .{"-" ** 60});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Tree = OST(i32, compareI32);
    var tree = Tree.init(allocator);
    defer tree.deinit();

    const inputs = [_]i32{ 15, 10, 20, 10, 5, 25, 30 };

    Printer.header();

    for (inputs) |val| {
        try tree.insert(val);
        Printer.row("INSERT", val, null);
    }

    Printer.divider();

    const search_queries = [_]i32{ 10, 20, 99 };
    for (search_queries) |q| {
        const found = tree.search(q);
        const res_dummy = if (found) NodeResult{ .index = 0, .data = q } else null;
        Printer.row("SEARCH", q, res_dummy);
    }

    Printer.divider();

    Printer.row("MIN", null, tree.min());
    Printer.row("MAX", null, tree.max());

    const pred_input = 18;
    Printer.row("PRED (<=)", pred_input, tree.predecessor(pred_input));

    const succ_input = 12;
    Printer.row("SUCC (>=)", succ_input, tree.successor(succ_input));

    Printer.divider();

    const del_val = 10;
    tree.delete(del_val); // Remove one instance (count 2 -> 1)
    Printer.row("DELETE", del_val, null);

    Printer.row("SEARCH", del_val, if (tree.search(del_val)) NodeResult{ .index = 0, .data = del_val } else null);

    std.debug.print("{s}\n", .{"=" ** 60});
}
