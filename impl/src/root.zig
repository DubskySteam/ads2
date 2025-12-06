// TODO: get(index)
// TODO: insert(index, value)
// TODO: Memory benchmark (plot?)
// TODO: next(), prev()
// TODO: Kontext parameterisierung
// TODO: Ausblick (Was wuerde noch gehen? Optimierung, Implementierung)
// TODO: Function benchmark

const std = @import("std");
const Allocator = std.mem.Allocator;
const Order = std.math.Order;
const node_mod = @import("node.zig");

/// Konfiguration für den Order‑Statistic‑Tree.
///
/// - use_freelist:
///   Schaltet einen einfachen Freelist‑Speicherpool für gelöschte Knoten ein.
///   Neue Knoten werden soweit möglich aus diesem Pool wiederverwendet.
///
/// - compact_sizes:
///   Wenn true, werden Teilbaumgrößen intern in einem kompakteren Typ geführt
///   (z.B. u32 statt usize), was die Knotengröße reduziert und den Cache
///   besser ausnutzen kann. Alle externen Indizes bleiben usize.
pub const OrderStatisticTreeConfig = struct {
    use_freelist: bool = true,
    compact_sizes: bool = false,
};

/// Erzeugt einen Order‑Statistic‑Tree über Schlüsseln vom Typ T.
///
/// Der Baum ist ein augmentierter Rot‑Schwarz‑Baum:
/// - Er ist als binärer Suchbaum über compareFn geordnet.
/// - Rot‑Schwarz‑Eigenschaften sorgen für Höhe O(log n).
/// - Jeder Knoten speichert die Größe seines Teilbaums (inkl. Duplikate),
///   sodass Rang‑Informationen (In‑Order‑Index) effizient berechnet werden
///   können.
///
/// Die API unterstützt:
/// - insert, delete, search, isEmpty
/// - min, max, predecessor, successor
pub fn OrderStatisticTree(
    comptime T: type,
    comptime compareFn: fn (a: T, b: T) std.math.Order,
    comptime cfg: OrderStatisticTreeConfig,
) type {
    return struct {
        const Self = @This();
        pub const Node = node_mod.Node(T);
        pub const NodeResult = node_mod.NodeResult(T);

        /// Interner Typ für Teilbaumgrößen (abhängig von compact_sizes).
        const SizeInt = if (cfg.compact_sizes) u32 else usize;

        /// Wurzelknoten des Baums (null, wenn leer).
        root: ?*Node,
        /// Allokator für Knotenspeicher.
        allocator: Allocator,
        /// Kopf der Freelist (nur genutzt, wenn use_freelist == true).
        free_list: ?*Node = null,

        /// Initialisiert einen leeren Baum mit gegebenem Allokator.
        pub fn init(allocator: Allocator) Self {
            return Self{
                .root = null,
                .allocator = allocator,
            };
        }

        /// Gibt alle von diesem Baum belegten Ressourcen frei.
        ///
        /// - Zerstört rekursiv alle noch im Baum befindlichen Knoten.
        /// - Gibt ggf. zusätzlich alle im Freelist‑Pool liegenden Knoten frei.
        pub fn deinit(self: *Self) void {
            if (self.root) |root| self.deinitNode(root);

            if (cfg.use_freelist) {
                var n = self.free_list;
                while (n) |node| {
                    const next = node.right;
                    self.allocator.destroy(node);
                    n = next;
                }
                self.free_list = null;
            }
        }

        /// Rekursive Hilfe zum Freigeben aller Knoten im Baum.
        fn deinitNode(self: *Self, node: *Node) void {
            if (node.left) |l| self.deinitNode(l);
            if (node.right) |r| self.deinitNode(r);
            self.allocator.destroy(node);
        }

        /// Allokiert einen neuen Knoten.
        ///
        /// Wenn use_freelist aktiviert ist, wird zuerst versucht, einen Knoten
        /// aus dem Freelist‑Pool zu recyceln, bevor der Allokator benutzt wird.
        fn allocNode(self: *Self) !*Node {
            if (cfg.use_freelist) {
                if (self.free_list) |n| {
                    self.free_list = n.right;
                    n.parent = null;
                    n.left = null;
                    n.right = null;
                    return n;
                }
            }
            return try self.allocator.create(Node);
        }

        /// Gibt einen Knoten frei.
        ///
        /// - Bei aktivem Freelist wird der Knoten nur in den Pool eingehängt.
        /// - Andernfalls wird er direkt an den Allokator zurückgegeben.
        fn freeNode(self: *Self, node: *Node) void {
            if (cfg.use_freelist) {
                node.parent = null;
                node.left = null;
                node.right = self.free_list;
                self.free_list = node;
                return;
            }
            self.allocator.destroy(node);
        }

        /// Fügt ein Element in den Baum ein.
        ///
        /// - Wenn der Schlüssel bereits existiert, wird nur count im Knoten
        ///   erhöht (Duplikate). Der Baum wächst strukturell nicht.
        /// - Andernfalls wird ein neuer Knoten angelegt und per Rot‑Schwarz‑
        ///   Fixup rebalanciert.
        /// - size wird auf dem Pfad zur Wurzel aktualisiert.
        pub fn insert(self: *Self, data: T) !void {
            var y: ?*Node = null;
            var x = self.root;

            // Letzte Vergleichsrichtung merken, um nach der Schleife
            // nicht erneut compareFn aufrufen zu müssen.
            var last_ord: ?Order = null;

            while (x) |node| {
                y = node;
                const ord = compareFn(data, node.data);
                last_ord = ord;

                switch (ord) {
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
                const ord = last_ord orelse unreachable;
                switch (ord) {
                    .lt => y.?.left = new_node,
                    .gt => y.?.right = new_node,
                    .eq => unreachable,
                }
            }

            self.updatePathSize(new_node);
            self.insertFixup(new_node);
        }

        /// Entfernt ein Vorkommen von `data` aus dem Baum.
        ///
        /// - Falls der Schlüssel nicht existiert, passiert nichts.
        /// - Bei count > 1 wird nur count dekrementiert, der physische
        ///   Knoten bleibt erhalten, und size wird entlang des Pfades
        ///   aktualisiert.
        /// - Bei count == 1 wird der Knoten wie in einem Rot‑Schwarz‑Baum
        ///   gelöscht und anschließend per deleteFixup rebalanciert.
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
                // Knoten mit zwei Kindern: Nachfolger im rechten Teilbaum suchen
                // und z durch diesen Nachfolger ersetzen.
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

        /// Prüft, ob `data` im Baum enthalten ist (mindestens ein Vorkommen).
        pub fn search(self: *Self, data: T) bool {
            return self.findNode(data) != null;
        }

        /// Liefert true, wenn der Baum leer ist.
        pub fn isEmpty(self: *Self) bool {
            return self.root == null;
        }

        /// Liefert das kleinste Element und dessen In‑Order‑Index.
        ///
        /// - Index ist immer 0, da es das erste Element in der Sortierung ist.
        /// - Gibt null zurück, wenn der Baum leer ist.
        pub fn min(self: *Self) ?NodeResult {
            const m = minimum(self.root orelse return null);
            return NodeResult{ .index = 0, .data = m.data };
        }

        /// Liefert das größte Element und den In‑Order‑Index des ersten
        /// Vorkommens dieses Schlüssels.
        ///
        /// - total_size entspricht der Gesamtzahl der Elemente im Baum.
        /// - Index = total_size - count(max_key).
        /// - Gibt null zurück, wenn der Baum leer ist.
        pub fn max(self: *Self) ?NodeResult {
            const m = maximum(self.root orelse return null);
            const total_size = if (self.root) |r| r.size else 0;
            return NodeResult{ .index = total_size - m.count, .data = m.data };
        }

        /// Liefert den Vorgänger (strict predecessor) von `data`.
        ///
        /// - Sucht das größte Element, das STRICT kleiner als `data` ist
        ///   (node.data < data).
        /// - Gibt Schlüssel und In‑Order‑Index des ersten Vorkommens zurück.
        /// - Gibt null zurück, falls kein solches Element existiert.
        pub fn predecessor(self: *Self, data: T) ?NodeResult {
            var current = self.root;
            var last_lt: ?*Node = null;

            while (current) |node| {
                switch (compareFn(data, node.data)) {
                    // data > node.data  => node.data < data: Kandidat, gehe rechts
                    .gt => {
                        last_lt = node;
                        current = node.right;
                    },
                    // data <= node.data => gehe links, Kandidat bleibt unverändert
                    .lt, .eq => current = node.left,
                }
            }

            const target = last_lt orelse return null;
            return NodeResult{ .index = self.getRank(target), .data = target.data };
        }

        /// Liefert den Nachfolger (strict successor) von `data`.
        ///
        /// - Sucht das kleinste Element, das STRICT größer als `data` ist
        ///   (node.data > data).
        /// - Gibt Schlüssel und In‑Order‑Index des ersten Vorkommens zurück.
        /// - Gibt null zurück, falls kein solches Element existiert.
        pub fn successor(self: *Self, data: T) ?NodeResult {
            var current = self.root;
            var last_gt: ?*Node = null;

            while (current) |node| {
                switch (compareFn(data, node.data)) {
                    // data < node.data  => node.data > data: Kandidat, gehe links
                    .lt => {
                        last_gt = node;
                        current = node.left;
                    },
                    // data >= node.data => gehe rechts, Kandidat bleibt unverändert
                    .gt, .eq => current = node.right,
                }
            }

            const target = last_gt orelse return null;
            return NodeResult{ .index = self.getRank(target), .data = target.data };
        }

        /// Liefert die Größe eines Teilbaums (0 bei null) im internen SizeInt-Typ.
        inline fn sizeOf(node: ?*Node) SizeInt {
            return if (node) |n| @intCast(n.size) else 0;
        }

        /// Aktualisiert das size‑Feld eines Knotens aus Kindern und count.
        inline fn updateSize(self: *Self, node: *Node) void {
            _ = self;
            const left: SizeInt = sizeOf(node.left);
            const right: SizeInt = sizeOf(node.right);
            const count_cast: SizeInt = @intCast(node.count);
            node.size = @intCast(left + right + count_cast);
        }

        /// Aktualisiert size entlang des Pfades von start_node bis zur Wurzel.
        fn updatePathSize(self: *Self, start_node: *Node) void {
            var curr: ?*Node = start_node;
            while (curr) |node| {
                self.updateSize(node);
                curr = node.parent;
            }
        }

        /// Sucht den Knoten mit Schlüssel data (oder null, falls nicht vorhanden).
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

        /// Liefert den minimalen Knoten im Teilbaum.
        fn minimum(node: *Node) *Node {
            var curr = node;
            while (curr.left) |l| curr = l;
            return curr;
        }

        /// Liefert den maximalen Knoten im Teilbaum.
        fn maximum(node: *Node) *Node {
            var curr = node;
            while (curr.right) |r| curr = r;
            return curr;
        }

        /// Berechnet den In‑Order‑Rang (0‑basiert) eines Knotens.
        ///
        /// Berücksichtigt:
        /// - Größe des linken Teilbaums,
        /// - count in allen Vorfahren, bei denen der aktuelle Knoten
        ///   im rechten Kind hängt.
        fn getRank(self: *Self, node: *Node) usize {
            _ = self;
            var r: usize = @intCast(sizeOf(node.left));
            var curr = node;

            while (curr.parent) |parent| {
                if (curr == parent.right) {
                    r += @as(usize, @intCast(sizeOf(parent.left))) + parent.count;
                }
                curr = parent;
            }
            return r;
        }

        /// Linksdrehung um Knoten x (klassische RB‑Rotation).
        ///
        /// Erhält die In‑Order‑Reihenfolge und passt danach lokal die size‑Werte
        /// von x und y an.
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

        /// Rechtsdrehung um Knoten y (klassische RB‑Rotation).
        ///
        /// Erhält die In‑Order‑Reihenfolge und passt danach lokal die size‑Werte
        /// von y und x an.
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

        /// Fixup nach Einfügen eines neuen roten Knotens.
        ///
        /// Löst Verstöße gegen die Rot‑Schwarz‑Invarianten (z.B. Doppelt‑Rot)
        /// durch geeignete Umfärbungen und Rotationen.
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

        /// Ersetzt Teilbaum u durch Teilbaum v (Standard‑Hilfsfunktion
        /// aus RB‑Löschalgorithmus).
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

        /// Fixup nach Löschen eines Knotens.
        ///
        /// Behandelt die klassischen Fälle des RB‑Löschens (Double‑Black etc.)
        /// und stellt die Rot‑Schwarz‑Eigenschaften durch Rotationen und
        /// Umfärbungen wieder her.
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

        /// Liefert den nächsten Schlüssel nach `data` (für existierenden Schlüssel).
        ///
        /// - Wenn `data` nicht im Baum ist, gibt null zurück.
        /// - Sonst: nächstes Element in In-Order-Reihenfolge.
        pub fn next(self: *Self, data: T) ?NodeResult {
            const node = self.findNode(data) orelse return null;

            // Wenn rechtes Kind existiert: minimum im rechten Teilbaum
            if (node.right) |r| {
                const succ = minimum(r);
                return NodeResult{ .index = self.getRank(succ), .data = succ.data };
            }

            // Sonst: erster Vorfahre, bei dem wir von links kommen
            var curr = node;
            while (curr.parent) |p| {
                if (curr == p.left) {
                    return NodeResult{ .index = self.getRank(p), .data = p.data };
                }
                curr = p;
            }

            return null; // war bereits der größte Schlüssel
        }

        /// Liefert den vorherigen Schlüssel vor `data` (für existierenden Schlüssel).
        ///
        /// - Wenn `data` nicht im Baum ist, gibt null zurück.
        /// - Sonst: vorheriges Element in In-Order-Reihenfolge.
        pub fn prev(self: *Self, data: T) ?NodeResult {
            const node = self.findNode(data) orelse return null;

            // Wenn linkes Kind existiert: maximum im linken Teilbaum
            if (node.left) |l| {
                const pred = maximum(l);
                return NodeResult{ .index = self.getRank(pred), .data = pred.data };
            }

            // Sonst: erster Vorfahre, bei dem wir von rechts kommen
            var curr = node;
            while (curr.parent) |p| {
                if (curr == p.right) {
                    return NodeResult{ .index = self.getRank(p), .data = p.data };
                }
                curr = p;
            }

            return null; // war bereits der kleinste Schlüssel
        }

        /// Liefert das Element an Position `index` in der sortierten Multimenge (0-basiert).
        ///
        /// - Gibt null zurück, wenn index >= Gesamtgröße.
        /// - O(log n) durch Abstieg mittels subtree sizes.
        pub fn select(self: *Self, index: usize) ?NodeResult {
            const idx_int: SizeInt = @intCast(index);
            var node = self.root orelse return null;
            var remaining: SizeInt = idx_int;

            while (true) {
                const left_size = sizeOf(node.left);

                if (remaining < left_size) {
                    // Ziel liegt im linken Teilbaum
                    node = node.left orelse return null;
                } else if (remaining < left_size + @as(SizeInt, @intCast(node.count))) {
                    // Ziel ist in diesem Knoten (eines der Duplikate)
                    return NodeResult{ .index = index, .data = node.data };
                } else {
                    // Ziel liegt im rechten Teilbaum
                    remaining -= left_size + @as(SizeInt, @intCast(node.count));
                    node = node.right orelse return null;
                }
            }
        }

        /// Fügt `data` ein und erwartet, dass es an Position `index` landet.
        ///
        /// - Wirft einen Fehler, falls die BST‑Ordnung das nicht zulässt.
        /// - Nützlich für "insert in sorted position", wenn Caller den Rang kennt.
        pub fn insertAt(self: *Self, index: usize, data: T) !void {
            try self.insert(data);

            // Validiere, dass das eingefügte Element tatsächlich an `index` liegt
            const node = self.findNode(data) orelse return error.InsertFailed;
            const actual_rank = self.getRank(node);

            if (actual_rank != index) {
                // Rollback: entferne das gerade eingefügte Element wieder
                self.delete(data);
                return error.InvalidInsertPosition;
            }
        }
    };
}
