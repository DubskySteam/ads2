const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const Tree = ost.OrderStatisticTree(i32, cmpI32, .{ .compact_sizes = true });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = Tree.init(allocator);
    defer tree.deinit();

    const stdout = std.debug;

    const inserts = [_]i32{ 50918, 1023981, 232, 2, 2093, 3952, 239252, 99999 };

    stdout.print("OrderStatisticTree demo\n\n", .{});
    stdout.print("Inserts:\n  value\n  -----\n", .{});

    for (inserts) |v| {
        try tree.insert(v);
        stdout.print("  {d}", .{v});
    }

    stdout.print("\n\n", .{});

    var ids: [32]usize = undefined;
    var vals: [32]i32 = undefined;
    var len: usize = 0;

    var cur_opt = tree.min();
    while (cur_opt) |nr| {
        if (len >= ids.len) break;
        ids[len] = nr.index;
        vals[len] = nr.data;
        len += 1;

        cur_opt = tree.successor(nr.data);
    }

    stdout.print("Tree in-order:\n", .{});
    stdout.print("ID  >>", .{});
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (i == 0) {
            stdout.print(" {d:>8}", .{ids[i]});
        } else {
            stdout.print(" | {d:>8}", .{ids[i]});
        }
    }
    stdout.print("\n", .{});

    stdout.print("VAL >>", .{});
    i = 0;
    while (i < len) : (i += 1) {
        if (i == 0) {
            stdout.print(" {d:>8}", .{vals[i]});
        } else {
            stdout.print(" | {d:>8}", .{vals[i]});
        }
    }
    stdout.print("\n\n", .{});

    const search_keys = [_]i32{ 99999, 11 };

    stdout.print("Search operations:\n", .{});
    stdout.print("  value | found\n", .{});
    stdout.print("  -------------\n", .{});

    for (search_keys) |k| {
        const found = tree.search(k);
        stdout.print("  {d:5} | {s}\n", .{ k, if (found) "yes" else "no" });
    }

    stdout.print("\n", .{});

    const query_keys = [_]i32{ 3000, 60000, 99999 };

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
