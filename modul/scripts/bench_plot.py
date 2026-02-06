import csv
from pathlib import Path
import matplotlib.pyplot as plt

SCRIPT_DIR = Path(__file__).resolve().parent
CSV_FILE = (SCRIPT_DIR / ".." / "bench.csv")
if not CSV_FILE.exists():
    CSV_FILE = (SCRIPT_DIR / "bench.csv")

OUT_DIR = SCRIPT_DIR / "plots"

def read_rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))

def quantile(sorted_vals, q):
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    pos = (len(sorted_vals) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = pos - lo
    return float(sorted_vals[lo]) * (1.0 - frac) + float(sorted_vals[hi]) * frac

def group_samples(rows, op, variant, key):
    d = {}
    for r in rows:
        if r["op"] != op or r["variant"] != variant:
            continue
        n = int(r["n"])
        v = float(r[key])
        d.setdefault(n, []).append(v)
    return d

def summarize(d):
    xs = sorted(d.keys())
    med, p25, p75 = [], [], []
    for x in xs:
        vals = sorted(d[x])
        med.append(quantile(vals, 0.50))
        p25.append(quantile(vals, 0.25))
        p75.append(quantile(vals, 0.75))
    return xs, med, p25, p75

def paired_speedup(rows, op):
    # n -> sample -> {base/opt: ns_per_op}
    by_n = {}
    for r in rows:
        if r["op"] != op:
            continue
        n = int(r["n"])
        s = int(r["sample"])
        by_n.setdefault(n, {}).setdefault(s, {})[r["variant"]] = float(r["ns_per_op"])

    xs = sorted(by_n.keys())
    meds, p25s, p75s = [], [], []
    for n in xs:
        ratios = []
        for s, d in by_n[n].items():
            if "base" in d and "opt" in d and d["opt"] != 0:
                ratios.append(d["base"] / d["opt"])
        ratios.sort()
        meds.append(quantile(ratios, 0.50) if ratios else None)
        p25s.append(quantile(ratios, 0.25) if ratios else None)
        p75s.append(quantile(ratios, 0.75) if ratios else None)
    return xs, meds, p25s, p75s

def plot_time(rows, op, out_name):
    base = group_samples(rows, op, "base", "ns_per_op")
    opt  = group_samples(rows, op, "opt",  "ns_per_op")

    xb, mb, b25, b75 = summarize(base)
    xo, mo, o25, o75 = summarize(opt)

    plt.figure(figsize=(6, 4))
    if xb:
        plt.plot(xb, mb, marker="o", label="base (median)")
        plt.fill_between(xb, b25, b75, alpha=0.2)
    if xo:
        plt.plot(xo, mo, marker="o", label="opt (median)")
        plt.fill_between(xo, o25, o75, alpha=0.2)

    plt.xscale("log"); plt.yscale("log")
    plt.xlabel("n"); plt.ylabel("ns/op")
    plt.title(f"Laufzeit: {op}")
    plt.grid(True, which="both", ls=":")
    handles, labels = plt.gca().get_legend_handles_labels()
    if labels:
        plt.legend()
    plt.tight_layout()
    plt.savefig(OUT_DIR / out_name, dpi=200)
    plt.close()

def plot_speedup_paired(rows, op, out_name):
    xs, med, p25, p75 = paired_speedup(rows, op)
    xs2, med2, p252, p752 = [], [], [], []
    for x, m, a, b in zip(xs, med, p25, p75):
        if m is None:
            continue
        xs2.append(x); med2.append(m); p252.append(a); p752.append(b)

    if not xs2:
        return

    plt.figure(figsize=(6, 4))
    plt.plot(xs2, med2, marker="o", label="paired median")
    plt.fill_between(xs2, p252, p752, alpha=0.2)

    plt.xscale("log")
    plt.xlabel("n"); plt.ylabel("Speedup (base/opt)")
    plt.title(f"Speedup (paired): {op}")
    plt.grid(True, which="both", ls=":")
    plt.legend()
    plt.tight_layout()
    plt.savefig(OUT_DIR / out_name, dpi=200)
    plt.close()

def plot_mem_insert_peak(rows, out_name):
    base = {}
    opt = {}
    exp = {}

    for r in rows:
        if r["op"] != "mem_insert_peak":
            continue
        n = int(r["n"])
        peak = int(float(r["mem_peak_bytes"]))
        expected = int(float(r["expected_node_bytes"]))
        if r["variant"] == "base":
            base[n] = peak
            exp[n] = expected
        elif r["variant"] == "opt":
            opt[n] = peak

    xs = sorted(set(base.keys()) | set(opt.keys()) | set(exp.keys()))
    if not xs:
        return

    plt.figure(figsize=(6, 4))
    plt.plot(xs, [base.get(x) for x in xs], marker="o", label="base peak")
    plt.plot(xs, [opt.get(x) for x in xs], marker="o", label="opt peak")
    plt.plot(xs, [exp.get(x) for x in xs], linestyle="--", label="expected n*sizeof(Node)")

    plt.xscale("log"); plt.yscale("log")
    plt.xlabel("n"); plt.ylabel("Bytes")
    plt.title("Speicher: Peak bei insert (O(n) Check)")
    plt.grid(True, which="both", ls=":")
    plt.legend()
    plt.tight_layout()
    plt.savefig(OUT_DIR / out_name, dpi=200)
    plt.close()

def print_speedup_table(rows, op):
    xs, med, p25, p75 = paired_speedup(rows, op)
    print(f"\n== speedup paired: {op} ==")
    print("n\tmedian\tp25\tp75")
    for n, m, a, b in zip(xs, med, p25, p75):
        if m is None:
            continue
        print(f"{n}\t{m:.4f}\t{a:.4f}\t{b:.4f}")

def main():
    OUT_DIR.mkdir(exist_ok=True)

    rows = read_rows(CSV_FILE)
    ops = sorted(set(r["op"] for r in rows))
    print("CSV:", CSV_FILE)
    print("ops:", ops)

    for op in ["time_search_hit", "time_predecessor", "time_cycles_insert_delete"]:
        if op in ops:
            print_speedup_table(rows, op)

    if "time_search_hit" in ops:
        plot_time(rows, "time_search_hit", "time_search_hit.png")
        plot_speedup_paired(rows, "time_search_hit", "speedup_search_hit_paired.png")

    if "time_predecessor" in ops:
        plot_time(rows, "time_predecessor", "time_predecessor.png")
        plot_speedup_paired(rows, "time_predecessor", "speedup_predecessor_paired.png")

    if "time_cycles_insert_delete" in ops:
        plot_time(rows, "time_cycles_insert_delete", "time_cycles_insert_delete.png")
        plot_speedup_paired(rows, "time_cycles_insert_delete", "speedup_cycles_paired.png")

    if "mem_insert_peak" in ops:
        plot_mem_insert_peak(rows, "memory_insert_peak.png")

    print("Wrote plots to:", OUT_DIR.resolve())

if __name__ == "__main__":
    main()
