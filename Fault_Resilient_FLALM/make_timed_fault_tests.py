#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
script=root/'scripts'/'make_core_fault_tb.py'
if not script.exists():
    raise SystemExit('Missing scripts/make_core_fault_tb.py')
# regenerate original tests, then add independent edge timestamp probes
import subprocess
subprocess.run(['python3',str(script)],check=True,cwd=root)
for n in (1024,2048):
    p=root/'fault_injection'/f'flalm_core_fault_tb_{n}.v'
    s=p.read_text()
    start_marker='    integer target_test;'
    assert start_marker in s
    add='''    integer clock_edges = 0;
    integer start_edge = -1;
    integer inject_edge = -1;
    integer alarm_edge = -1;
    integer alarm_check_edge = -1;
    integer completion_edge = -1;
    always @(posedge clk) begin
        clock_edges = clock_edges + 1;
        #2;
        if (start_edge >= 0 && tests == target_test &&
            alarm_edge < 0 &&
            dut.u_core.u_pe.u_kar.security_fault === 1'b1) begin
            alarm_edge = clock_edges;
        end
    end
'''
    s=s.replace(start_marker,add+start_marker,1)
    init='''            if (tests == target_test) begin
                checks_before ='''
    assert init in s
    s=s.replace(init,'''            if (tests == target_test) begin
                start_edge = clock_edges;
                inject_edge = -1;
                alarm_edge = -1;
                checks_before =''',1)
    mark='''                        force dut.u_core.u_pe.u_kar.r1 = fault_value;'''
    assert mark in s
    s=s.replace(mark,'''                        inject_edge = clock_edges;
'''+mark,1)
    mark='''            // 4. read the result'''
    assert mark in s
    s=s.replace(mark,'''            completion_edge = clock_edges;
'''+mark,1)
    mark='''                if (z_got !== z_exp)
                    $display("FAULT_TEST_PASS'''
    assert mark in s
    s=s.replace(mark,'''                $display("TIMING start_edge=%0d inject_edge=%0d alarm_edge=%0d done_edge=%0d absolute_cycles=%0d expected=%0d local_cnt=%0d detect_latency_edges=%0d", start_edge, inject_edge, alarm_edge, completion_edge, completion_edge-start_edge, cyc_exp, cnt, alarm_edge-inject_edge);
                if (alarm_edge < inject_edge || completion_edge-start_edge != cyc_exp) begin
                    $display("TIMING_WARNING: inspect start-to-done accounting or alarm alignment");
                end
                if (z_got !== z_exp)
                    $display("FAULT_TEST_PASS''',1)
    p.write_text(s)
    print('Instrumented',p)
