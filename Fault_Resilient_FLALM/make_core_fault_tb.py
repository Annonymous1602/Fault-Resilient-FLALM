#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
original=root/'baseline'/'tb'
out=root/'fault_injection'
out.mkdir(exist_ok=True)
for n in (1024,2048):
    src=original/f'flalm_tb_{n}.v'
    if not src.exists():
        raise SystemExit(f'Missing baseline testbench: {src}')
    s=src.read_text()
    old=f'module flalm_tb_{n};'
    assert s.count(old)==1
    s=s.replace(old, f'module flalm_core_fault_tb_{n};', 1)
    marker='    integer tests, errors, i, cnt;'
    assert s.count(marker)==1
    s=s.replace(marker, marker+'''
    integer target_test;
    integer injected;
    reg [8*16:1] target_mode;
    reg [W-1:0] fault_value;
    integer checks_before;
''',1)
    # Fault injection starts after start pulse, but only on selected test.
    marker="            start  = 1'b0;"
    assert s.count(marker)==1
    s=s.replace(marker, marker+'''
            if (tests == target_test) begin
                checks_before = dut.u_core.u_pe.u_kar.security_checks;
                fork
                    begin : inject_one_fault
                        // Wait for first reconstruction-valid Karatsuba operation.
                        wait (dut.u_core.u_pe.u_kar.m_res1_vld === 1'b1);
                        // At the next negedge the r1 component is stable.
                        @(negedge clk);
                        fault_value = dut.u_core.u_pe.u_kar.r1 ^ {{(W-1){1'b0}},1'b1};
                        force dut.u_core.u_pe.u_kar.r1 = fault_value;
                        $display("FAULT_INJECTED test=%0s t=%0t bit=0 location=karatsuba.r1",name,$time);
                        @(negedge clk);
                        release dut.u_core.u_pe.u_kar.r1;
                        injected = 1;
                        $display("FAULT_RELEASED t=%0t",$time);
                    end
                join_none
            end
''',1)
    marker='            // 5. check\n'
    assert s.count(marker)==1
    s=s.replace(marker, '''            // A targeted test is classified separately from the golden pass tests.
            if (tests == target_test) begin
                if (injected != 1) begin
                    $display("FAULT_TEST_FAIL injection did not execute");
                    $fatal(1);
                end
                if (dut.u_core.u_pe.u_kar.security_checks <= checks_before) begin
                    $display("FAULT_TEST_FAIL no arithmetic operation was checked");
                    $fatal(1);
                end
                if (dut.u_core.u_pe.u_kar.security_fault !== 1'b1) begin
                    $display("FAULT_TEST_FAIL checker did not detect injected fault");
                    $fatal(1);
                end
                if (z_got !== z_exp)
                    $display("FAULT_TEST_PASS detected=1 final_output_corrupted=1 cycles=%0d",cnt);
                else
                    $display("FAULT_TEST_PASS detected=1 final_output_corrupted=0 (masked or corrected) cycles=%0d",cnt);
                $finish;
            end
            // 5. check
''',1)
    marker="        tests  = 0;"
    assert s.count(marker)==1
    s=s.replace(marker, '''        target_mode = "GMM";
        if ($value$plusargs("target=%s", target_mode)) begin end
        if (target_mode == "SMM") target_test = 4;
        else if (target_mode == "GMM") target_test = 0;
        else begin
            $display("Unknown +target=%0s", target_mode);
            $fatal(1);
        end
        injected = 0;
        checks_before = 0;
'''+marker,1)
    (out/f'flalm_core_fault_tb_{n}.v').write_text(s)
    print('Generated',out/f'flalm_core_fault_tb_{n}.v')
