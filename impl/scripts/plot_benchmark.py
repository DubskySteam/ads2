#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import sys

def plot_results(csv_path):
    df = pd.read_csv(csv_path)
    
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('Order-Statistic Tree Performance Profile', fontsize=16)
    
    # 1. Time vs Size for each operation
    ax1 = axes[0, 0]
    for op in df['operation'].unique():
        data = df[df['operation'] == op]
        ax1.plot(data['size'], data['time_ns'] / 1e6, marker='o', label=op)
    ax1.set_xlabel('Tree Size (n)')
    ax1.set_ylabel('Time (ms)')
    ax1.set_title('Operation Time vs Tree Size')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # 2. Time per element (normalized)
    ax2 = axes[0, 1]
    for op in df['operation'].unique():
        data = df[df['operation'] == op]
        time_per_elem = data['time_ns'] / data['size']
        ax2.plot(data['size'], time_per_elem, marker='o', label=op)
    ax2.set_xlabel('Tree Size (n)')
    ax2.set_ylabel('Time per Element (ns)')
    ax2.set_title('Amortized Cost per Operation')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # 3. Memory usage
    ax3 = axes[1, 0]
    insert_data = df[df['operation'] == 'insert']
    ax3.plot(insert_data['size'], insert_data['memory_bytes'] / 1024, marker='o', color='green')
    ax3.set_xlabel('Tree Size (n)')
    ax3.set_ylabel('Memory (KB)')
    ax3.set_title('Memory Usage')
    ax3.grid(True, alpha=0.3)
    
    # 4. Throughput (ops/sec)
    ax4 = axes[1, 1]
    for op in df['operation'].unique():
        data = df[df['operation'] == op]
        throughput = (data['size'] / (data['time_ns'] / 1e9))
        ax4.plot(data['size'], throughput / 1e6, marker='o', label=op)
    ax4.set_xlabel('Tree Size (n)')
    ax4.set_ylabel('Throughput (M ops/s)')
    ax4.set_title('Operation Throughput')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('benchmark_results.png', dpi=300, bbox_inches='tight')
    print("Plot saved to benchmark_results.png")
    plt.show()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python plot_benchmark.py results.csv")
        sys.exit(1)
    plot_results(sys.argv[1])
