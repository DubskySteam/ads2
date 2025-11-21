# Order Statistic Tree (Zig)

Eine speichereffiziente Implementierung eines **Order Statistic Trees** basierend auf einem erweiterten Rot-Schwarz-Baum.
Entwickelt für minimale Laufzeitkomplexität und geringstmöglichen Speicherverbrauch.

## Features

- **Generisch**: Funktioniert mit jedem Datentyp `T` (via `comptime`).
- **Speichereffizient**: Duplikate werden gezählt (`count`), nicht mehrfach gespeichert.
- **Statistisch**: Zugriff auf Elemente nach Rang (Index) in $O(\log n)$.
- **Single-Threaded**: Optimiert für sequenzielle Performance ohne Locking-Overhead.

## Struktur & Speicherlayout

Jeder Knoten speichert nur die Nutzlast `data`. Metadaten (Größe, Anzahl) ermöglichen die Index-Berechnung.

```c
const Node = struct {
    data: T,
    size: usize, 
    count: usize,
    
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    
    color: enum { Red, Black },
};
```

## Zeitkomplexität

| Operation | Komplexität | Beschreibung |
| :--- | :--- | :--- |
| `insert(x)` | $O(\log n)$ | Fügt `x` ein oder inkrementiert `count` bei Duplikaten. |
| `delete(x)` | $O(\log n)$ | Dekrementiert `count` oder entfernt Knoten (falls `count` == 1). |
| `search(x)` | $O(\log n)$ | Prüft Existenz eines Wertes. |
| `rank(x)` | $O(\log n)$ | Ermittelt den Index eines Elements in der sortierten Folge. |
| `select(i)` | $O(\log n)$ | Findet das $i$-te Element (genutzt für Median/Statistik). |
| `min() / max()` | $O(\log n)$ | Gibt Extremwerte + Index zurück. |
| `pred / succ` | $O(\log n)$ | Findet Vorgänger/Nachfolger + Index. |

## Nutzung (Beispiel)

```
const OST = OrderStatisticTree(i32);
var tree = OST.init(allocator);
defer tree.deinit();

try tree.insert(10);
try tree.insert(20);
try tree.insert(10); // count für 10 wird erhöht

// Suche
if (tree.search(10)) {
    // ...
}

// Statistik
const min = tree.min(); // { index: 0, data: 10 }
const pred = tree.predecessor(15); // { index: 1, data: 10 } (da 10 zweimal da ist)
```

## Build & Test

```
zig build test
zig build run
```