#!/usr/bin/env python3

import csv
import sys
from pathlib import Path
from collections import Counter

def analyze(filename):

    with open(filename, newline="") as f:
        rows = list(csv.DictReader(f))

    if not rows:
        raise RuntimeError("Empty campaign file")

    total = len(rows)

    injected = sum(int(r["injected"]) for r in rows)
    detected = sum(int(r["detected"]) for r in rows)
    corrupted = sum(int(r["corrupt"]) for r in rows)

    silent = sum(
        int(r["corrupt"]) == 1 and
        int(r["detected"]) == 0
        for r in rows
    )

    detected_corrupted = sum(
        int(r["corrupt"]) == 1 and
        int(r["detected"]) == 1
        for r in rows
    )

    latencies = [
        int(r["alarm"]) - int(r["inject"])
        for r in rows
        if int(r["injected"]) == 1
        and int(r["detected"]) == 1
        and int(r["alarm"]) >= int(r["inject"])
    ]

    invalid_timing = sum(
        int(r["absolute_cycles"]) != int(r["expected"])
        for r in rows
    )

    bits = Counter(int(r["bit"]) for r in rows)

    print("\n========================================")
    print("FLALM FAULT CAMPAIGN ANALYSIS")
    print("========================================")

    print("File:", filename)

    print("Total trials:", total)
    print("Injected:", injected)
    print("Detected:", detected)
    print("Corrupted outputs:", corrupted)
    print("Silent corruptions:", silent)

    if injected:
        print(
            "Detection rate: %.3f%%"
            % (100 * detected / injected)
        )

    if corrupted:
        print(
            "Corrupting-fault detection: %.3f%%"
            % (100 * detected_corrupted / corrupted)
        )

    if latencies:
        print("Minimum detection latency:", min(latencies))
        print("Maximum detection latency:", max(latencies))

        print(
            "Average detection latency: %.3f"
            % (sum(latencies) / len(latencies))
        )

        print("Detection latency distribution:")
        for latency, count in sorted(Counter(latencies).items()):
            print("  %d cycles: %d trials" % (latency, count))

    print("Unique bit positions tested:", len(bits))
    print("Trials with unexpected completion timing:", invalid_timing)

    if injected != total:
        print("WARNING: Some trials did not inject a fault")

    print("========================================\n")


if __name__ == "__main__":

    if len(sys.argv) < 2:
        print("Usage: python3 analyze_fault_campaign.py file.csv ...")
        sys.exit(1)

    for filename in sys.argv[1:]:
        analyze(Path(filename))
