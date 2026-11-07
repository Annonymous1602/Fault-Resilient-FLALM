#!/usr/bin/env python3

import csv
import re
import subprocess
from pathlib import Path
from collections import Counter

ROOT = Path.cwd()
BASE = ROOT / "phase30_host_fault_campaign_20261028"

VECTOR = ROOT / "phase18/cpa/datasets/cpa_00000.hex"
LOG_DIR = BASE / "logs/spatial_5120"
CSV_PATH = BASE / "csv/spatial_5120_results.csv"

TARGETS = ("r1", "r2")
OPS = (1, 2, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72)
BITS = range(128)

LOG_DIR.mkdir(parents=True, exist_ok=True)

def get(text, name):
    matches = re.findall(
        rf"(?m)^{re.escape(name)}=([^\r\n]+)",
        text
    )
    return matches[-1].strip() if matches else None

def yes(value):
    return value == "1"

def same_hex(a, b):
    try:
        return (
            a is not None
            and b is not None
            and int(a, 16) == int(b, 16)
        )
    except (TypeError, ValueError):
        return False

rows = []

for target in TARGETS:

    exe = BASE / f"build/fault_{target}.vvp"

    if not exe.is_file():
        raise FileNotFoundError(exe)

    for op in OPS:

        print(f"===== TARGET={target} OP={op} =====", flush=True)

        for bit in BITS:

            cmd = [
                "vvp",
                str(exe),
                f"+vectors={VECTOR}",
                f"+fault_op_index={op}",
                f"+fault_bit={bit}",
            ]

            try:
                result = subprocess.run(
                    cmd,
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )

                text = result.stdout + "\n" + result.stderr
                exit_code = result.returncode

            except subprocess.TimeoutExpired as exc:

                def decode(value):
                    if value is None:
                        return ""
                    if isinstance(value, bytes):
                        return value.decode(errors="replace")
                    return value

                text = (
                    decode(exc.stdout)
                    + "\n"
                    + decode(exc.stderr)
                    + "\nSIMULATION_TIMEOUT\n"
                )
                exit_code = -1

            log = LOG_DIR / (
                f"{target}_op{op:02d}_bit{bit:03d}.log"
            )

            log.write_text(text)

            original = get(text, "SPATIAL_ORIGINAL")
            faulty = get(text, "SPATIAL_FAULTY")

            bitflip_valid = False

            try:
                bitflip_valid = (
                    int(original, 16) ^ int(faulty, 16)
                ) == (1 << bit)
            except (ValueError, TypeError):
                pass

            injection_valid = all([
                get(text, "SPATIAL_TARGET") == target,
                get(text, "SPATIAL_OPERATION_INDEX") == str(op),
                get(text, "SPATIAL_FAULT_BIT") == str(bit),
                bitflip_valid,
                "SPATIAL_INJECTION_FAIL" not in text,
            ])

            first = get(text, "FIRST_ATTEMPT_RESULT")
            final = get(text, "FINAL_RESULT")
            expected = get(text, "EXPECTED_RESULT")

            first_correct = same_hex(first, expected)
            final_correct = same_hex(final, expected)

            first_corrupted = yes(
                get(text, "FIRST_ATTEMPT_CORRUPTED")
            )

            alarm = yes(get(text, "FIRST_ATTEMPT_ALARM"))
            fault_seen = yes(get(text, "FAULT_SEEN"))
            recovered = yes(get(text, "RECOVERY_SUCCESS"))
            recovery_failed = yes(get(text, "RECOVERY_FAILED"))
            valid = yes(get(text, "RESULT_VALID"))

            attempts = get(text, "ATTEMPTS")

            complete = (
                text.count("CORRELATED_EXPERIMENT_COMPLETE") == 1
            )

            common = all([
                exit_code == 0,
                complete,
                injection_valid,
                alarm,
                fault_seen,
                recovered,
                not recovery_failed,
                valid,
                final_correct,
                attempts == "2",
                first is not None,
                first_corrupted != first_correct,
            ])

            if valid and not final_correct:
                category = "SILENT_DATA_CORRUPTION"

            elif (
                injection_valid
                and first_corrupted
                and not alarm
            ):
                category = "DETECTION_MISSED"

            elif common and first_corrupted:
                category = "DETECTED_CORRUPTION_RECOVERED"

            elif common and not first_corrupted:
                category = "DETECTED_BENIGN_REEXECUTED"

            else:
                category = "REVIEW"

            row = {
                "target": target,
                "operation": op,
                "bit": bit,
                "injection_valid": int(injection_valid),
                "target_nonzero": get(text, "SPATIAL_NONZERO"),
                "first_corrupted": int(first_corrupted),
                "first_alarm": int(alarm),
                "fault_seen": int(fault_seen),
                "attempts": attempts,
                "recovery_success": int(recovered),
                "recovery_failed": int(recovery_failed),
                "result_valid": int(valid),
                "first_correct": int(first_correct),
                "final_correct": int(final_correct),
                "classification": category,
                "exit_code": exit_code,
            }

            rows.append(row)

            if category == "REVIEW" or category == "SILENT_DATA_CORRUPTION":
                print(
                    f"REVIEW target={target} op={op} "
                    f"bit={bit} classification={category}",
                    flush=True,
                )

        selected = [
            r for r in rows
            if r["target"] == target
            and r["operation"] == op
        ]

        print(
            f"TARGET={target} OP={op} "
            f"CLASSIFICATIONS="
            f"{dict(Counter(r['classification'] for r in selected))}",
            flush=True,
        )

CSV_PATH.parent.mkdir(parents=True, exist_ok=True)

with CSV_PATH.open("w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=list(rows[0].keys()),
    )
    writer.writeheader()
    writer.writerows(rows)

counts = Counter(r["classification"] for r in rows)

print()
print("===== FINAL SPATIAL CAMPAIGN =====")
print("TOTAL_EXPERIMENTS=", len(rows))
print("VALID_INJECTIONS=", sum(r["injection_valid"] for r in rows))
print("FIRST_ALARMS=", sum(r["first_alarm"] for r in rows))
print("FIRST_CORRUPTED=", sum(r["first_corrupted"] for r in rows))
print("FINAL_CORRECT=", sum(r["final_correct"] for r in rows))
print("CLASSIFICATIONS=", dict(counts))
print("CSV_REPORT=", CSV_PATH)

bad = sum(
    counts[name]
    for name in (
        "REVIEW",
        "DETECTION_MISSED",
        "SILENT_DATA_CORRUPTION",
    )
)

if len(rows) != 512 or bad:
    print("SPATIAL_512_REQUIRES_REVIEW")
    raise SystemExit(1)

print("SPATIAL_512_CLASSIFICATION_PASS")
