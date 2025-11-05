### Wonach suche ich?
Die geforderte Datenstruktur ist ein dynamischer, geordneter Container, der neben insert/delete/search auch predecessor/successor/min/max liefert
und dabei zusätzlich den In‑Order‑Index i des gefundenen Elements zurückgibt.

### Auswahl einer passenden Basisstruktur

Bei der Suche nach einer geeigneten Basis fuer meine Datenstruktur habe ich mir die verschiedenen Variationen von Baeumen angeschaut.
Dabei habe ich mich fuer einen **Rot-Schwarz-Baum** entschieden, da dieser eine gute Balance zwischen Einfuege-, Loesch- und Suchoperationen bietet.
Ein einfacher binaerer Baum kann im Durchschnitt schneller sein, faellt im Worst-Case-Szenario aber weit zurueck was die Performance und Komplexitaet angeht.
Alternativ haette ich auch einen **AVL-Baum** in Betracht ziehen koennen, aber mit Rot-Schwarz-Baeumen habe ich schon etwas Erfahrung gesammelt was verschiedene Implementierungen angeht, daher habe ich mich gegen den AVL-Baum entschieden.

Ein Rot-Schwarz-Baum grantiert uns eine Hoehe von O(log n), was bedeutet, dass alle Operationen wie Einfuegen, Loeschen und Suchen in logarithmischer Zeit durchgefuehrt werden koennen.
Angesicht der Anforderungen an die Datenstruktur scheint mit dieser Baum am besten geeignet.

![](img/ref2.jpg)

### Operationen der Datenstruktur
- insert(x): Fügt x als neuen Schlüssel ein. Duplikate erlauben wir durch zaehlen.

- delete(x): Entfernt x, falls vorhanden. Standard‑BST‑Loeschen mit tauschen der Nachfolger und rekusiver Anpassung des Baums.

search(x) → bool: Liefert, ob x enthalten ist.​

isEmpty() → bool: Prueft, ob der Baum leer ist.​

min()/max() → ⟨i, x⟩: Liefert kleinstes bzw. groeßtes Element samt Index.​

predecessor(z) → ⟨i, x⟩: Größtes Element mit x ≤ z samt Index i.​

successor(z) → ⟨i, x⟩: Kleinstes Element mit x ≥ z samt Index i.​

### Struktur des Rot-Schwarz-Baums

![](img/ref1.svg)

Bei der Struktur meines Baumes reicht die gewohnliche Definition eines Rot-Schwarz-Baums nicht aus, da ich zusaetzlich die Groesse der Teilbaeume und die Anzahl der gleichen Schluessel speichern muss um das einfuegen von gleichen Schluesseln und die Berechnung des Ranges zu log(n) zu ermoeglichen.

```c
enum Color {
    Red,
    Black,
}

const RSTreeNode = struct {
    color: Color, // Rot oder Schwarz
    key: KeyType, // Der Schluesel fuer die Suche
    value: ValueType, // Der zugehoerige Wert
    left: ?*RSTreeNode, // Linker Kindknoten
    right: ?*RSTreeNode, // Rechter Kindknoten
    parent: ?*RSTreeNode, //Elternknoten
    size: usize, // Anzahl der Knoten im Teilbaum
    count: usize, // Anzahl der gleichen Schluesel
};
```

### Lautzeitanalyse und Speicherverbrauch

- isEmpty(): O(1)

`Wir pruefen nur ob die Root null ist. Boolean Operation.`

- search(key): O(log n)

`O(log n) da die Hoehe des Baumes log n ist und wir in jedem Schritt die Haelfte der Knoten ignorieren koennen.`

- insert/delete(key, value): O(log n)

`O(log n) da die Hoehe des Baumes log n ist und wir in jedem Schritt die Haelfte der Knoten ignorieren koennen. Das Einfuegen/Loeschen selbst ist eine konstante Operation.`

- min, max: O(log n)

`O(log n) Gleicher Grund wie bei search.`

- predecessor(key), successor(key): O(log n)

#### Speicherbedarf
Der Speicherbedarf der Datenstruktur ist O(n), wobei n die Anzahl der Elemente im Baum ist.
Es gibt lediglich als Zusatz ein Farbbit pro Knoten und die Groesse der Teilbaeume, was den Speicherbedarf nicht wesentlich erhoeht. (Ich habe es aber nicht benchmarked.)

### Zig-Code (Pseudocode)

**Ich bin direkt mit Zig eingestiegen, weil ich mit tatsaechlichen kleinen Implementierungen besser Gedanken verfolgen kann. (Und um die Komplexitaet zu testen und zu validieren ob ich gerade Quatch schreibe.)**

Insert:
```c
function insert(node, x):
    if node == null:
        return new Node(x,count=1)
    if x < node.key:
        node.left = insert(node.left, x)
    else if x > node.key:
        node.right = insert(node.right, x)
    else:
        node.count += 1
    node.subtree_size = size(node.left) + size(node.right) + node.count
    // neue Balanceierung
    return rebalance(node)

```

predecessor/successor: Sollte so funktionieren?
```c
function predecessor(root, z):
    node = root; best = null
    while node != null:
        if node.key <= z:
            best = node
            node = node.right  // suche noch groeßere <= z
        else:
            node = node.left
    if best == null: return (null,null)  // kein Vorgaenger
    // best.key <= z ist der gesuchte Wert
    i = size(best.left) + best.count  // letztes Vorkommen von best.key
    return (i, best.key)

function successor(root, z):
    node = root; best = null
    while node != null:
        if node.key >= z:
            best = node
            node = node.left  // suche noch kleinere >= z
        else:
            node = node.right
    if best == null: return (null,null)
    // best.key >= z ist der gesuchte Wert
    i = size(best.left) + 1  // erstes Vorkommen von best.key
    return (i, best.key)
```

### Quellen / Hilfsquellen

- https://www.geeksforgeeks.org/dsa/time-complexities-of-different-data-structures/
- https://en.wikipedia.org/wiki/Predecessor_problem
- https://en.wikipedia.org/wiki/Self-balancing_binary_search_tree
- https://en.wikipedia.org/wiki/Van_Emde_Boas_tree
- https://ls2-web.cs.tu-dortmund.de/~mamicoja/dap2/slides/lec_redblack.pdf
- https://groups.csail.mit.edu/mac/projects/info/schemedocs/ref-manual/html/scheme_113.html
- https://dtu.ac.in/Web/Departments/CSE/faculty/lect/DSA_MK_Lect8.pdf
- https://www.baeldung.com/cs/skip-lists


Zum "ausprobieren":
- https://www.cs.usfca.edu/~galles/visualization/RedBlack.html