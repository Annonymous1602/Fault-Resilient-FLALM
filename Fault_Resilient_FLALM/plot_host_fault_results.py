#!/usr/bin/env python3

import csv
from pathlib import Path
from collections import Counter

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch

BASE = Path("phase30_host_fault_campaign_20261028")
INPUT = BASE / "csv/host_7680_audited.csv"
OUT = BASE / "figures"
OUT.mkdir(parents=True, exist_ok=True)

TARGETS = ["r1", "r2", "r3"]
OPS = [1, 2, 4, 8, 12, 16, 20, 24, 28, 32,
       36, 40, 44, 48, 52, 56, 60, 64, 68, 72]

CORRUPT = "DETECTED_CORRUPTION_RECOVERED"
BENIGN = "DETECTED_BENIGN"

with INPUT.open(newline="") as f:
    rows = list(csv.DictReader(f))

assert len(rows) == 7680, "Unexpected number of rows"

counts = {
    target: Counter(
        row["classification"]
        for row in rows
        if row["target"] == target
    )
    for target in TARGETS
}

# IEEE-friendly figure settings.
plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 8,
    "axes.labelsize": 8,
    "axes.titlesize": 9,
    "xtick.labelsize": 7,
    "ytick.labelsize": 7,
    "legend.fontsize": 7,
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    "savefig.dpi": 300,
})

# ======================================================
# FIGURE 1: NORMALIZED FAULT CLASSIFICATION
# ======================================================

x = np.arange(len(TARGETS))

recovered = np.array([
    counts[t][CORRUPT] / 2560 * 100 for t in TARGETS
])

benign = np.array([
    counts[t][BENIGN] / 2560 * 100 for t in TARGETS
])

fig, ax = plt.subplots(figsize=(3.45, 2.45))

ax.bar(
    x, recovered,
    width=0.58,
    color="#326f91",
    label="Corruption detected and recovered"
)

ax.bar(
    x, benign,
    width=0.58,
    bottom=recovered,
    color="#e6ab55",
    hatch="//",
    edgecolor="#5a5a5a",
    linewidth=0.4,
    label="Detected benign"
)

for i in range(3):
    ax.text(
        x[i], recovered[i] / 2,
        f"{int(counts[TARGETS[i]][CORRUPT]):,}",
        ha="center", va="center",
        color="white", fontsize=8,
        fontweight="bold"
    )

    if benign[i] > 0:
        ax.text(
            x[i], recovered[i] + benign[i] / 2,
            f"{int(counts[TARGETS[i]][BENIGN])}",
            ha="center", va="center",
            fontsize=7
        )

ax.set_xticks(x, [r"$r_1$", r"$r_2$", r"$r_3$"])
ax.set_ylabel("Fault outcomes (%)")
ax.set_ylim(0, 108)
ax.set_yticks([0, 25, 50, 75, 100])
ax.grid(axis="y", alpha=0.20)
ax.set_axisbelow(True)

ax.legend(
    loc="upper center",
    bbox_to_anchor=(0.5, -0.14),
    frameon=False,
    ncol=1
)

fig.tight_layout()

fig.savefig(
    OUT / "host_fault_classification.pdf",
    bbox_inches="tight"
)
fig.savefig(
    OUT / "host_fault_classification.png",
    bbox_inches="tight"
)
plt.close(fig)

# ======================================================
# FIGURE 2: SPATIAL-TEMPORAL FAULT OUTCOME MAP
# ======================================================

# 0 = detected/recovered
# 1 = detected benign
# 2 = other outcome (should not occur in audited data)

state = {
    CORRUPT: 0,
    BENIGN: 1
}

cmap = ListedColormap([
    "#326f91",
    "#e6ab55",
    "#b44343"
])

fig, axes = plt.subplots(
    3, 1,
    figsize=(6.9, 5.0),
    sharex=True
)

for ax, target in zip(axes, TARGETS):
    matrix = np.full((len(OPS), 128), 2, dtype=int)

    for row in rows:
        if row["target"] != target:
            continue

        op = int(row["operation"])
        bit = int(row["bit"])
        category = row["classification"]

        matrix[OPS.index(op), bit] = state.get(category, 2)

    ax.imshow(
        matrix,
        aspect="auto",
        interpolation="nearest",
        origin="lower",
        cmap=cmap,
        vmin=0,
        vmax=2
    )

    ax.set_ylabel(
        f"{target}\nOperation",
        fontsize=8
    )

    ax.set_yticks(
        [0, 3, 7, 11, 15, 19],
        [str(OPS[i]) for i in [0, 3, 7, 11, 15, 19]]
    )

    ax.set_xticks([0, 31, 63, 95, 127])

axes[-1].set_xlabel("Injected bit position")

legend = [
    Patch(
        facecolor="#326f91",
        label="Detected and recovered"
    ),
    Patch(
        facecolor="#e6ab55",
        hatch="//",
        label="Detected benign"
    )
]

fig.legend(
    handles=legend,
    loc="lower center",
    bbox_to_anchor=(0.5, -0.03),
    ncol=2,
    frameon=False
)

fig.tight_layout(rect=[0, 0.05, 1, 1])

fig.savefig(
    OUT / "host_fault_heatmap.pdf",
    bbox_inches="tight"
)
fig.savefig(
    OUT / "host_fault_heatmap.png",
    bbox_inches="tight"
)
plt.close(fig)

print("HOST_PUBLICATION_FIGURES_CREATED")
print("TOTAL_ROWS=", len(rows))
for target in TARGETS:
    print(
        target,
        dict(counts[target])
    )
print("OUTPUT_DIR=", OUT.resolve())
