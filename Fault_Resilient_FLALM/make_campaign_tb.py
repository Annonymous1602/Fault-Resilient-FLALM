#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
for n in (1024,2048):
    p=root/'fault_injection'/f'flalm_core_fault_tb_{n}.v'
    if not p.is_file():
        raise SystemExit(f'Missing {p}. First run bash scripts/run_timed_fault.sh')
    s=p.read_text()
    s=s.replace(f'module flalm_core_fault_tb_{n};',f'module flalm_campaign_tb_{n};',1)
    s=s.replace('    integer target_test;','''    integer target_bit, target_occurrence, valid_seen, fault_seen;
    reg [W-1:0] fault_mask;
    integer target_test;''',1)
    s=s.replace('''                fork
                    begin : inject_one_fault''','''                valid_seen = 0;
                fork
                    begin : inject_one_fault''',1)
    s=s.replace('''                        wait (dut.u_core.u_pe.u_kar.m_res1_vld === 1'b1);
                        // At the next negedge the r1 component is stable.
                        @(negedge clk);
                        fault_value = dut.u_core.u_pe.u_kar.r1 ^ {{(W-1){1'b0}},1'b1};''','''                        while (valid_seen < target_occurrence) begin
                            @(posedge clk);
                            #1;
                            if (dut.u_core.u_pe.u_kar.m_res1_vld === 1'b1)
                                valid_seen = valid_seen + 1;
                        end
                        @(negedge clk);
                        fault_mask = {W{1'b0}};
                        fault_mask[target_bit] = 1'b1;
                        fault_value = dut.u_core.u_pe.u_kar.r1 ^ fault_mask;''',1)
    s=s.replace('''$display("FAULT_INJECTED test=%0s t=%0t bit=0 location=karatsuba.r1",name,$time);''','''$display("FAULT_INJECTED test=%0s t=%0t bit=%0d occurrence=%0d location=karatsuba.r1",name,$time,target_bit,target_occurrence);''',1)
    # no mandatory alarm; collect all outcomes
    start=s.index('                if (dut.u_core.u_pe.u_kar.security_fault !== 1\'b1) begin')
    stop=s.index('                $finish;',start)
    s=s[:start]+'''                $display("CAMPAIGN_RESULT width=%0d mode=%0s bit=%0d occurrence=%0d injected=%0d detected=%0d corrupt=%0d start=%0d inject=%0d alarm=%0d done=%0d absolute_cycles=%0d expected=%0d", N, target_mode, target_bit, target_occurrence, injected, dut.u_core.u_pe.u_kar.security_fault === 1'b1, z_got !== z_exp, start_edge, inject_edge, alarm_edge, completion_edge, completion_edge-start_edge, cyc_exp);
                if (completion_edge-start_edge != cyc_exp || done !== 1'b1)
                    $fatal(1,"Unexpected completion timing");
'''+s[stop:]
    hook='''        injected = 0;
        checks_before = 0;'''
    assert hook in s
    s=s.replace(hook,'''        target_bit=0;
        target_occurrence=1;
        if ($value$plusargs("bit=%d",target_bit)) begin end
        if ($value$plusargs("occurrence=%d",target_occurrence)) begin end
        if (target_bit < 0 || target_bit >= W || target_occurrence < 1)
            $fatal(1,"Bad fault parameters");
'''+hook,1)
    out=root/'fault_injection'/f'flalm_campaign_tb_{n}.v'
    out.write_text(s)
    print('Generated',out)
