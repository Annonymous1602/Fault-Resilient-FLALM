#!/usr/bin/env python3

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

monitor = "dut.u_core.u_pe.u_kar"

for n in (1024, 2048):

    src = ROOT / "baseline" / "tb" / f"flalm_tb_{n}.v"
    dst = ROOT / "tb" / f"secure_flalm_tb_{n}.v"

    s = src.read_text()

    old_module = f"module flalm_tb_{n};"
    new_module = f"module secure_flalm_tb_{n};"

    assert old_module in s
    s = s.replace(old_module, new_module, 1)

    # Add checker assertions before the final test summary.
    marker = "        if (errors == 0)\n"

    assert marker in s, "Could not find test summary"

    check = f"""
        // Verify that the integrated security checker was active.
        if ({monitor}.security_checks == 0) begin
            errors = errors + 1;
            $display("SECURITY FAIL: No Karatsuba operations checked");
        end

        if ({monitor}.security_fault !== 1'b0) begin
            errors = errors + 1;
            $display("SECURITY FAIL: Unexpected arithmetic alarm");
        end

        if ({monitor}.security_checks > 0 &&
            {monitor}.security_fault === 1'b0) begin
            $display("SECURITY PASS: %0d operations checked, no alarm",
                     {monitor}.security_checks);
        end

"""

    s = s.replace(marker, check + marker, 1)

    dst.write_text(s)

    print("Generated:", dst)
