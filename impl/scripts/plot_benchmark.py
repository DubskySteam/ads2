#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt

CSV = "../profile.csv"

TESTS_SPEED = [
    "insert_build",
    "delete_to_empty",
    "search",
    "select",
    "successor",
    "churn_delete_insert",
]

def plot_lines(ax, sub, x, y, title, ylabel, logx=True, logy=False):
    sub = sub.sort_values(["n", "config"])
    for cfg in ["freelist", "no_freelist"]:
        s = sub[sub["config"] == cfg]
        if len(s) == 0:
            continue
        ax.plot(s[x], s[y], marker="o", linewidth=2, label=cfg)

    if logx:
        ax.set_xscale("log", base=2)
    if logy:
        ax.set_yscale("log")

    ax.set_title(title)
    ax.set_xlabel("n")
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)

def main():
    df = pd.read_csv(CSV)

    # Ensure the expected configs exist
    print("configs:", sorted(df["config"].unique()))
    print("tests:", sorted(df["test"].unique()))

    # One big figure: 3 rows x 3 cols
    fig, axes = plt.subplots(3, 3, figsize=(18, 12), constrained_layout=True)
    fig.suptitle("OST profiling: speed + allocator behaviour (freelist vs no_freelist)", fontsize=16)

    # 6 speed plots
    for i, test in enumerate(TESTS_SPEED):
        r = i // 3
        c = i % 3
        sub = df[df["test"] == test]
        plot_lines(
            axes[r, c],
            sub,
            x="n",
            y="ops_per_sec",
            title=f"{test} ops/s",
            ylabel="ops/s",
            logx=True,
            logy=False,
        )

    # churn alloc_calls (this should show freelist advantage)
    sub_churn = df[df["test"] == "churn_delete_insert"]
    plot_lines(
        axes[2, 0],
        sub_churn,
        x="n",
        y="alloc_calls",
        title="churn: alloc_calls",
        ylabel="alloc() calls",
        logx=True,
        logy=False,
    )

    # churn total_alloc_bytes (also shows freelist advantage)
    plot_lines(
        axes[2, 1],
        sub_churn,
        x="n",
        y="total_alloc_bytes",
        title="churn: total_alloc_bytes",
        ylabel="bytes",
        logx=True,
        logy=False,
    )

    # insert_build peak_bytes 
    sub_build = df[df["test"] == "insert_build"]
    plot_lines(
        axes[2, 2],
        sub_build,
        x="n",
        y="peak_bytes",
        title="insert_build: peak_bytes",
        ylabel="bytes",
        logx=True,
        logy=False,
    )


    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", frameon=True)

    fig.savefig("all_plots.png", dpi=200)
    print("Wrote all_plots.png")

if __name__ == "__main__":
    main()
