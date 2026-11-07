#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for n in (1024, 2048):
    for kind in ('normal', 'fault'):
        if kind == 'normal':
            src = root/'baseline'/'tb'/f'flalm_tb_{n}.v'
            oldmod = f'module flalm_tb_{n};'
        else:
            src = root/'fault_injection'/f'flalm_core_fault_tb_{n}.v'
            oldmod = f'module flalm_core_fault_tb_{n};'
        s = src.read_text()
        newmod = f'module containment_{kind}_tb_{n};'
        assert s.count(oldmod)==1, f'Module header missing in {src}'
        s = s.replace(oldmod, newmod, 1)
        s = s.replace('dut.u_core.', 'dut.u_flalm.u_core.')
        s = s.replace('dut.u_ram.', 'dut.u_flalm.u_ram.')
        s = s.replace('    flalm #(', '    flalm_secure #(', 1)
        needle = '.busy(busy), .done(done), .z_sel(z_sel));'
        assert s.count(needle)==1, f'Instance missing in {src}'
        s = s.replace(needle, '.busy(busy), .done(done), .z_sel(z_sel),\n        .security_fault(security_fault), .result_valid(result_valid));', 1)
        needle = '    wire          busy, done, z_sel;'
        assert s.count(needle)==1
        s = s.replace(needle, needle+'\n    wire security_fault, result_valid;',1)
        if kind == 'normal':
            needle = '            // 5. check\n'
            assert s.count(needle)==1
            s=s.replace(needle, '''            if (security_fault !== 1'b0 || result_valid !== 1'b1) begin
                $display("CONTAINMENT_FAIL normal operation: alarm=%b valid=%b", security_fault, result_valid);
                $fatal(1);
            end
            // 5. check
''',1)
        else:
            needle = '                if (z_got !== z_exp)'
            assert needle in s
            s=s.replace(needle, '''                if (security_fault !== 1'b1 || result_valid !== 1'b0 || done !== 1'b1) begin
                    $display("CONTAINMENT_FAIL fault operation: alarm=%b valid=%b done=%b", security_fault, result_valid, done);
                    $fatal(1);
                end
                $display("CONTAINMENT_PASS fault rejected: alarm=1 valid=0 raw_done=1");
                if (z_got !== z_exp)''',1)
        dest = root/'fault_injection'/f'containment_{kind}_tb_{n}.v'
        dest.write_text(s)
        print('Generated',dest)
