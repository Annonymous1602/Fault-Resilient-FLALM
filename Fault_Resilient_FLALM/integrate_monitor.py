#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
k=root/'secure_rtl'/'karatsuba.v'
if not k.exists():
    raise SystemExit('Missing secure_rtl/karatsuba.v. Copy baseline RTL first.')
s=k.read_text()
needle='    assign m_res1_vld = vld[5];'
if needle not in s:
    raise SystemExit('Could not find expected Karatsuba assignment; no changes made.')
if 'u_security_residue' in s:
    print('Monitor already integrated'); raise SystemExit(0)
insert='''
    // Security monitor, kept outside the functional arithmetic path.
    wire security_fault;
    wire security_checked;
    wire [31:0] security_checks;
    karatsuba_residue_monitor #(.W(W), .P(8191)) u_security_residue (
        .clk(clk), .rst(rst), .issue(issue), .a(a), .b(b),
        .m_res1(m_res1), .m_res2(m_res2), .m_res1_vld(m_res1_vld),
        .alarm(security_fault), .checked(security_checked),
        .checks(security_checks)
    );
'''
s=s.replace(needle,needle+'\n'+insert)
k.write_text(s)
print('Integrated standalone monitor into',k)
