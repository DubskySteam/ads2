# Order Statistic Tree

A memory‑efficient implementation of an **Order Statistic Tree** based on an augmented red‑black tree.

## Features

- **Generic**: Works with any type `T` as long as you provide a total ordering function `fn (a: T, b: T) std.math.Order`.
- **Memory‑efficient duplicates**: Equal keys are not stored as separate nodes; a node keeps a `count` of duplicates.
- **Order statistics**: Query elements by rank (0‑based index in sorted order) in \(O(\log n)\).
- **Min / max with index**: `min()` / `max()` return both the value and its global index.
- **Predecessor / successor**: Find strict predecessor and successor of a key, including their indices.
- **Single‑threaded**: Optimized for sequential performance without synchronization overhead.

## Data structure

Each node only stores the payload `data` and the minimal metadata required for balancing and rank queries. The `size` field is the total number of elements in the subtree (including duplicates via `count`), which allows rank computations in \(O(\log n)\).

```
const Node = struct {
    data: T,

    size: usize, // subtree size including count
    count: usize,

    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,

    color: enum { Red, Black },
};
```

## Asymptotic complexity

| Operation         | Time complexity | Description                                                                 |
| :---------------- | :------------- | :-------------------------------------------------------------------------- |
| `insert(x)`       | \(O(\log n)\)  | Inserts `x` or increments `count` for an existing key.                     |
| `delete(x)`       | \(O(\log n)\)  | Decrements `count` or removes the node if `count == 1`.                    |
| `search(x)`       | \(O(\log n)\)  | Checks if a value exists in the tree.                                      |
| rank of `x`       | \(O(\log n)\)  | Computes the index of `x` in the sorted multiset (via subtree `size`).     |
| select by index   | \(O(\log n)\)  | Finds the element at a given index (order statistic).                      |
| `min()` / `max()` | \(O(\log n)\)  | Returns extreme values together with their global indices.                 |
| predecessor       | \(O(\log n)\)  | Strict predecessor of a key (largest value `< key`) plus its index.        |
| successor         | \(O(\log n)\)  | Strict successor of a key (smallest value `> key`) plus its index.         |

All operations are worst‑case logarithmic because the underlying tree is a red‑black tree.

## Benchmarks

### Throughput

| Operation | Elements | Time [s] | elems/ns    | elems/ms     | elems/s        |
| :-------- | -------: | -------: | ----------: | -----------: | -------------: |
| insert    | 5.000.000 | 0.632535 | 0.007905    | 7.904     | 7.904.700   |
| search    | 5.000.000 | 0.304060 | 0.016444    | 16.444    | 16.444.122  |
| delete    | 5.000.000 | 0.352360 | 0.014190    | 14.190    | 14.190.032  |

Interpretation:

- **Insert**: ~7.9 million inserts per second for distinct `i32` values while maintaining order statistics.
- **Search**: ~16.4 million successful searches per second.
- **Delete**: ~14.2 million deletions per second, including rebalancing and size updates.


## Usage

The tree is exposed as a generic type `OrderStatisticTree(T, compareFn)` from `src/root.zig`.

```
const std = @import("std");
const ost = @import("ost");

fn cmpI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const OST = ost.OrderStatisticTree(i32, cmpI32);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = OST.init(allocator);
    defer tree.deinit();

    try tree.insert(10);
    try tree.insert(20);
    try tree.insert(10); // duplicate, count for 10 is incremented

    // membership
    if (tree.search(10)) {
        // ...
    }

    // order statistics
    if (tree.min()) |min_res| {
        // min_res.index == 0, min_res.data == 10
    }

    if (tree.predecessor(20)) |pred| {
        // strict predecessor of 20
        // pred.data == 10, pred.index == 0 (because 10 appears twice)
    }
}
```

## Building, tests, and demo

From the project root containing `build.zig`:

```
# run unit tests for the library and scenario tests
zig build test

# run the demo (prints a small example tree and operations)
zig build demo

# run benchmarks (ReleaseFast)
zig build bench
```

- `src/root.zig` contains the library implementation (no `main`).
- `src/tests.zig` contains correctness tests for insert/search/min/max/predecessor/successor and duplicates.
- `examples/demo.zig` shows a small scripted scenario, including an in‑order grid of `(index, value)`.
- `benchmarks/main.zig` runs the microbenchmarks and writes a CSV file with raw timings and derived throughput.