#!/usr/bin/env python3
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parents[1]
SRC, DST = ROOT/'secure_rtl', ROOT/'synth_secure_rtl'
if not SRC.exists(): raise SystemExit('Missing secure_rtl directory')
DST.mkdir(exist_ok=True)
for f in SRC.glob('*.v'): shutil.copy2(f, DST/f.name)
def edit(name, replacements):
    p = DST/name
    s = p.read_text()
    for old,new in replacements:
        if old not in s: raise RuntimeError(f'{name}: missing pattern {old[:60]!r}')
        s = s.replace(old,new,1)
    p.write_text(s)
edit('karatsuba.v', [
 ('output             m_res1_vld    // 1 in cycle c+5 of every issued operation',
  'output             m_res1_vld,   // 1 in cycle c+5\n    output             security_fault_out'),
 ('    wire security_fault;',
  '    wire security_fault;\n    assign security_fault_out = security_fault;')])
edit('pe_v2.v', [
 ('output [W-1:0]     q_i         // q[i] register',
  'output [W-1:0]     q_i,        // q[i] register\n    output             security_fault_out'),
 ('        .m_res1_vld(m_res1_vld)\n',
  '        .m_res1_vld(m_res1_vld),\n        .security_fault_out(security_fault_out)\n')])
edit('flalm_core.v', [
 ('ram_o1, ram_o2\n);', 'ram_o1, ram_o2, security_fault_out\n);'),
 ('    output             z_sel;', '    output             z_sel;\n    output             security_fault_out;'),
 ('        .d_access(d_access), .rb1(rb1), .rb2(rb2), .q_i(q_i));',
  '        .d_access(d_access), .rb1(rb1), .rb2(rb2), .q_i(q_i),\n        .security_fault_out(security_fault_out));')])
edit('flalm.v', [
 ('clk, rst, start, len, smm_en, mp, busy, done, z_sel\n);',
  'clk, rst, start, len, smm_en, mp, busy, done, z_sel, security_fault_out\n);'),
 ('    output             z_sel;', '    output             z_sel;\n    output             security_fault_out;'),
 ('        .busy(busy), .done(done), .z_sel(z_sel),',
  '        .busy(busy), .done(done), .z_sel(z_sel),\n        .security_fault_out(security_fault_out),')])
wrapper = ROOT/'security'/'flalm_secure.v'
if not wrapper.exists(): raise RuntimeError('Missing security/flalm_secure.v')
s = wrapper.read_text()
old = '        .mp(mp), .busy(busy), .done(done), .z_sel(z_sel)'
new = '        .mp(mp), .busy(busy), .done(done), .z_sel(z_sel),\n        .security_fault_out(security_fault)'
if old not in s: raise RuntimeError('Wrapper connection mismatch')
s = s.replace(old,new,1)
old = '    assign security_fault = u_flalm.u_core.u_pe.u_kar.security_fault;'
if old not in s: raise RuntimeError('Missing wrapper hierarchical assignment')
s = s.replace(old,'    // Alarm connected through module ports, not hierarchy.',1)
(DST/'flalm_secure.v').write_text(s)
print('PASS: generated synth_secure_rtl with explicit alarm ports')
