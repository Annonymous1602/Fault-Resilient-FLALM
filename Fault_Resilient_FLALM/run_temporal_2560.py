#!/usr/bin/env python3

import csv
import re
import subprocess
from pathlib import Path
from collections import Counter

ROOT = Path.cwd()

BASE = ROOT / "phase30_host_fault_campaign_20261028"

EXE = BASE / "build/fault_r3.vvp"

VECTOR = ROOT / "phase18/cpa/datasets/cpa_00000.hex"

LOG_DIR = BASE / "logs/temporal_2560"

CSV_PATH = BASE / "csv/temporal_2560_results.csv"

OPS = [1, 2, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72]

BITS = range(128)

assert EXE.is_file(), f"Missing executable: {EXE}"
assert VECTOR.is_file(), f"Missing vector: {VECTOR}"

LOG_DIR.mkdir(parents=True, exist_ok=True)
CSV_PATH.parent.mkdir(parents=True, exist_ok=True)


def field(text, name):
    matches = re.findall(
        rf"(?m)^{re.escape(name)}=([^\r\n]+)",
        text
    )
    return matches[-1].strip() if matches else None


def is_one(value):
    return value in ("1", "1'b1")


def same_hex(a, b):
    try:
        return (
            a is not None
            and b is not None
            and int(a, 16) == int(b, 16)
        )
    except ValueError:
        return False


rows = []

print("========================================")
print("P3-E TEMPORAL CORRELATED FAULT CAMPAIGN")
print("========================================")
print("OPERATIONS:", OPS)
print("BIT_POSITIONS:", 128)
print("TOTAL_ATTEMPTS:", len(OPS) * 128)
print()

for op in OPS:

    print(f"===== OPERATION {op} =====", flush=True)

    for bit in BITS:

        cmd = [
            "vvp",
            str(EXE),
            f"+vectors={VECTOR}",
            f"+fault_bit={bit}",
            f"+fault_op_index={op}",
        ]

        try:
            result = subprocess.run(
                cmd,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=30,
            )

            output = result.stdout + "\n" + result.stderr

            exit_code = result.returncode

        except subprocess.TimeoutExpired as exc:

            stdout = exc.stdout or b""
            stderr = exc.stderr or b""

            if isinstance(stdout, bytes):
                stdout = stdout.decode(errors="replace")

            if isinstance(stderr, bytes):
                stderr = stderr.decode(errors="replace")

            output = stdout + "\n" + stderr
            exit_code = -1

        log_path = (
            LOG_DIR
            / f"op_{op:02d}_bit_{bit:03d}.log"
        )

        log_path.write_text(output)

        injected_op = field(
            output, "INJECTED_OPERATION"
        )

        r3_nonzero = field(
            output, "R3_NONZERO"
        )

        injected = field(
            output, "INJECTION_OCCURRED"
        )

        corrupted = field(
            output, "FIRST_ATTEMPT_CORRUPTED"
        )

        alarm = field(
            output, "FIRST_ATTEMPT_ALARM"
        )

        fault_seen = field(
            output, "FAULT_SEEN"
        )

        attempts = field(
            output, "ATTEMPTS"
        )

        recovery = field(
            output, "RECOVERY_SUCCESS"
        )

        recovery_failed = field(
            output, "RECOVERY_FAILED"
        )

        result_valid = field(
            output, "RESULT_VALID"
        )

        final_result = field(
            output, "FINAL_RESULT"
        )

        expected_result = field(
            output, "EXPECTED_RESULT"
        )

        classification = field(
            output, "CORRELATED_CLASSIFICATION"
        )

        final_correct = same_hex(
            final_result,
            expected_result
        )

        injection_line = re.findall(
            r"(?m)^CORRELATED_FAULT_INJECTED "
            r"bit=(\d+) "
            r"original_r3=([0-9a-fA-F]+) "
            r"faulty_r3=([0-9a-fA-F]+) "
            r"original_residue=([0-9a-fA-F]+) "
            r"time=(\d+)",
            output,
        )

        injected_bit = None
        original_r3 = None
        faulty_r3 = None
        injection_time = None
        direct_corruption = False

        if len(injection_line) == 1:

            entry = injection_line[0]

            injected_bit = int(entry[0])
            original_r3 = entry[1]
            faulty_r3 = entry[2]
            injection_time = int(entry[4])

            direct_corruption = (
                int(original_r3, 16)
                ^ int(faulty_r3, 16)
            ) == (1 << bit)

        complete = (
            output.count(
                "CORRELATED_EXPERIMENT_COMPLETE"
            ) == 1
        )

        injection_valid = all([
            injected_bit == bit,
            injected_op == str(op),
            is_one(injected),
            len(injection_line) == 1,
            direct_corruption,
            "CORRELATED_DATAPATH_INJECTION_FAIL"
                not in output,
            "CORRELATED_RESIDUE_FORCE_FAIL"
                not in output,
        ])

        strict_pass = all([
            exit_code == 0,
            complete,
            injection_valid,
            is_one(corrupted),
            is_one(alarm),
            is_one(fault_seen),
            attempts == "2",
            is_one(recovery),
            recovery_failed == "0",
            is_one(result_valid),
            final_correct,
            classification == "RECOVERED",
        ])

        sdc = (
            is_one(result_valid)
            and not final_correct
        )

        if strict_pass:
            status = "PASS"
        elif sdc:
            status = "SDC"
        elif not injection_valid:
            status = "INVALID_INJECTION"
        elif exit_code != 0:
            status = "SIMULATION_FAILURE"
        else:
            status = "REVIEW"

        row = {
            "operation": op,
            "bit": bit,
            "injected_op": injected_op,
            "injection_time": injection_time,
            "r3_nonzero": r3_nonzero,
            "original_r3": original_r3,
            "faulty_r3": faulty_r3,
            "injection_valid": int(injection_valid),
            "direct_corruption": int(
                direct_corruption
            ),
            "first_corrupted": corrupted,
            "first_alarm": alarm,
            "fault_seen": fault_seen,
            "attempts": attempts,
            "recovery_success": recovery,
            "recovery_failed": recovery_failed,
            "result_valid": result_valid,
            "final_correct": int(final_correct),
            "classification": classification,
            "sdc": int(sdc),
            "exit_code": exit_code,
            "strict_pass": int(strict_pass),
            "status": status,
        }

        rows.append(row)

        if not strict_pass:

            print(
                f"REVIEW op={op} bit={bit} "
                f"status={status} "
                f"alarm={alarm} "
                f"corrupted={corrupted} "
                f"class={classification}",
                flush=True,
            )

    op_rows = [
        r for r in rows
        if r["operation"] == op
    ]

    print(
        f"OP={op} "
        f"PASS={sum(r['strict_pass'] for r in op_rows)}/128 "
        f"SDC={sum(r['sdc'] for r in op_rows)} "
        f"NONZERO_R3={sum(r['r3_nonzero'] == '1' for r in op_rows)}",
        flush=True,
    )

    print()


columns = list(rows[0].keys())

with CSV_PATH.open("w", newline="") as f:

    writer = csv.DictWriter(
        f,
        fieldnames=columns
    )

    writer.writeheader()
    writer.writerows(rows)


print("========================================")
print("FINAL TEMPORAL FAULT CAMPAIGN SUMMARY")
print("========================================")

print("TOTAL_ATTEMPTS=", len(rows))

print(
    "VALID_INJECTIONS=",
    sum(r["injection_valid"] for r in rows),
    sep=""
)

print(
    "FIRST_CORRUPTED=",
    sum(r["first_corrupted"] == "1" for r in rows),
    sep=""
)

print(
    "FIRST_ALARM=",
    sum(r["first_alarm"] == "1" for r in rows),
    sep=""
)

print(
    "RECOVERED=",
    sum(r["recovery_success"] == "1" for r in rows),
    sep=""
)

print(
    "FINAL_CORRECT=",
    sum(r["final_correct"] for r in rows),
    sep=""
)

print(
    "NONZERO_R3_EXPERIMENTS=",
    sum(r["r3_nonzero"] == "1" for r in rows),
    sep=""
)

print(
    "OBSERVED_SDC=",
    sum(r["sdc"] for r in rows),
    sep=""
)

print(
    "STRICT_PASS=",
    sum(r["strict_pass"] for r in rows),
    sep=""
)

print(
    "STATUS_COUNTS=",
    dict(Counter(r["status"] for r in rows))
)

print("CSV_REPORT=", CSV_PATH)

if len(rows) == 640 and all(
    r["strict_pass"] for r in rows
):
    print("TEMPORAL_640_STRICT_PASS")
else:
    print("TEMPORAL_640_REQUIRES_REVIEW")
    raise SystemExit(1)
