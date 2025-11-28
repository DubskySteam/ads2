const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const Tree = ost.OrderStatisticTree(i32, cmpI32);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = Tree.init(allocator);
    defer tree.deinit();

    const stdout = std.debug;

    stdout.print("OrderStatisticTree demo\n\n", .{});

    const inserts = [_]i32{ 5, 3, 8, 1, 4, 7, 9, 2, 6, 10 };

    stdout.print("Inserts:\n", .{});
    stdout.print("  value\n", .{});
    stdout.print("  -----\n", .{});

    for (inserts) |v| {
        try tree.insert(v);
        stdout.print("  {d}\n", .{v});
    }

    stdout.print("\n", .{});

    stdout.print("Tree elements in order (index, value):\n", .{});
    stdout.print("  idx | val\n", .{});
    stdout.print("  ----------\n", .{});

    var current = tree.min();
    while (current) |node_res| {
        stdout.print("  {d:3} | {d}\n", .{ node_res.index, node_res.data });
        current = tree.successor(node_res.data);
    }

    const search_keys = [_]i32{ 4, 11 };

    stdout.print("Search operations:\n", .{});
    stdout.print("  value | found\n", .{});
    stdout.print("  -------------\n", .{});

    for (search_keys) |k| {
        const found = tree.search(k);
        stdout.print("  {d:5} | {s}\n", .{ k, if (found) "yes" else "no" });
    }

    stdout.print("\n", .{});

    const query_keys = [_]i32{ 5, 6 };

    stdout.print("Predecessor / Successor:\n", .{});
    stdout.print("  key | pred(idx,val)   | succ(idx,val)\n", .{});
    stdout.print("  --------------------------------------\n", .{});

    for (query_keys) |k| {
        const pred = tree.predecessor(k);
        const succ = tree.successor(k);

        if (pred) |p| {
            if (succ) |s| {
                stdout.print(
                    "  {d:3} | {d:3},{d:3}       | {d:3},{d:3}\n",
                    .{ k, p.index, p.data, s.index, s.data },
                );
            } else {
                stdout.print(
                    "  {d:3} | {d:3},{d:3}       |  -, -\n",
                    .{ k, p.index, p.data },
                );
            }
        } else {
            if (succ) |s| {
                stdout.print(
                    "  {d:3} |  -, -            | {d:3},{d:3}\n",
                    .{ k, s.index, s.data },
                );
            } else {
                stdout.print(
                    "  {d:3} |  -, -            |  -, -\n",
                    .{k},
                );
            }
        }
    }

    stdout.print("\nDone.\n", .{});
}
