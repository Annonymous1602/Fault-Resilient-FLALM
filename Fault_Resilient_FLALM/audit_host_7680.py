#!/usr/bin/env python3

import csv
from pathlib import Path
from collections import Counter

ROOT = Path.cwd()
BASE = ROOT / "phase30_host_fault_campaign_20261028"
OPS = [1, 2, 4, 8, 12, 16, 20, 24, 28, 32,
       36, 40, 44, 48, 52, 56, 60, 64, 68, 72]

SOURCES = [
    ("r3", BASE / "csv/temporal_2560_results.csv"),
    ("spatial", BASE / "csv/spatial_5120_results.csv")
]

def read_rows(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def flag(row, key):
    return str(row.get(key, "")).strip() == "1"

results = []
problems = []
seen = set()

for source, path in SOURCES:
    for row in read_rows(path):

        target = row.get("target") if source == "spatial" else "r3"

        try:
            op = int(row["operation"])
            bit = int(row["bit"])
        except (ValueError, KeyError, TypeError):
            problems.append(("INVALID_INDEX", row))
            continue

        identity = (target, op, bit)

        if identity in seen:
            problems.append(("DUPLICATE", identity))
            continue

        seen.add(identity)

        if target not in ("r1", "r2", "r3"):
            problems.append(("INVALID_TARGET", identity))

        if op not in OPS or not (0 <= bit < 128):
            problems.append(("INVALID_LOCATION", identity))

        if not flag(row, "injection_valid"):
            problems.append(("INJECTION_NOT_CONFIRMED", identity))

        if row.get("exit_code", "") != "0":
            problems.append(("SIMULATION_EXIT", identity, row.get("exit_code")))

        if not flag(row, "first_alarm"):
            problems.append(("MISSING_FIRST_ALARM", identity))

        if not flag(row, "fault_seen"):
            problems.append(("FAULT_NOT_SEEN", identity))

        if not flag(row, "final_correct"):
            problems.append(("FINAL_RESULT_INCORRECT", identity))

        if not flag(row, "result_valid"):
            problems.append(("RESULT_NOT_VALID", identity))

        if flag(row, "recovery_failed"):
            problems.append(("RECOVERY_FAILED", identity))

        if not flag(row, "recovery_success"):
            problems.append(("RECOVERY_NOT_SUCCESSFUL", identity))

        try:
            attempts = int(row.get("attempts", "-1"))
        except ValueError:
            attempts = -1

        if attempts != 2:
            problems.append(("UNEXPECTED_ATTEMPTS", identity, attempts))

        if source == "r3":
            try:
                injected_op = int(row.get("injected_op", "-1"))
            except ValueError:
                injected_op = -1

            if injected_op != op:
                problems.append(("OPERATION_MISMATCH", identity, injected_op))

        corrupted = flag(row, "first_corrupted")
        alarm = flag(row, "first_alarm")
        final_correct = flag(row, "final_correct")

        if corrupted and alarm and final_correct:
            classification = "DETECTED_CORRUPTION_RECOVERED"
        elif not corrupted and alarm and final_correct:
            classification = "DETECTED_BENIGN"
        elif corrupted and not alarm:
            classification = "SDC_OR_UNDETECTED_ERROR"
        else:
            classification = "OTHER_REVIEW"

        results.append({
            "target": target,
            "operation": op,
            "bit": bit,
            "classification": classification,
            "injection_valid": row.get("injection_valid"),
            "first_corrupted": row.get("first_corrupted"),
            "first_alarm": row.get("first_alarm"),
            "fault_seen": row.get("fault_seen"),
            "attempts": row.get("attempts"),
            "recovery_success": row.get("recovery_success"),
            "final_correct": row.get("final_correct"),
            "exit_code": row.get("exit_code"),
        })

expected = {
    (target, op, bit)
    for target in ("r1", "r2", "r3")
    for op in OPS
    for bit in range(128)
}

for identity in sorted(expected - seen):
    problems.append(("MISSING_EXPERIMENT", identity))

print("===== INDEPENDENT HOST AUDIT =====")
print("EXPECTED_EXPERIMENTS=", len(expected))
print("AUDITED_EXPERIMENTS=", len(results))
print("PROBLEMS=", len(problems))

for target in ("r1", "r2", "r3"):
    counts = Counter(
        r["classification"]
        for r in results if r["target"] == target
    )
    print(f"TARGET={target} CLASSIFICATIONS={dict(counts)}")

print("TOTAL_CLASSIFICATIONS=",
      dict(Counter(r["classification"] for r in results)))

for problem in problems[:30]:
    print("AUDIT_PROBLEM:", problem)

if problems or len(results) != len(expected):
    raise SystemExit("HOST_7680_AUDIT_FAILED")

output = BASE / "csv/host_7680_audited.csv"

with output.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print("AUDITED_CSV=", output)
print("HOST_7680_INDEPENDENT_AUDIT_PASS")
