#!/usr/bin/env python3
"""Standalone residue-checker fault campaign; NOT an integrated FLALM campaign."""
import argparse
import csv
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--width', type=int, default=1024)
p.add_argument('--mode', choices=['GMM', 'SMM'], default='GMM')
p.add_argument('--fault', choices=['single_bit'], default='single_bit')
p.add_argument('--trials', type=int, default=1000)
p.add_argument('--seed', type=int, default=2027)
a = p.parse_args()
if a.width not in (1024, 2048):
    p.error('This first-stage script labels only 1024/2048 experiments; checker itself uses 128-bit words')
if a.trials < 1:
    p.error('--trials must be positive')
root = pathlib.Path(__file__).resolve().parent.parent
build = root / 'build'
results = root / 'fault_injection' / 'results'
build.mkdir(parents=True, exist_ok=True)
results.mkdir(parents=True, exist_ok=True)
exe = build / 'residue_fault_campaign.vvp'
csvfile = results / f'residue_word128_{a.width}_{a.mode}_{a.fault}_seed{a.seed}.csv'
cmd = ['iverilog', '-g2012', '-s', 'fault_campaign_tb', '-o', str(exe),
       str(root / 'security' / 'residue_mul_check.v'),
       str(root / 'fault_injection' / 'fault_campaign_tb.v')]
subprocess.run(cmd, check=True)
subprocess.run(['vvp', str(exe), f'+TRIALS={a.trials}', f'+SEED={a.seed}', f'+CSV={csvfile}'],check=True)
with csvfile.open(newline='') as f:
    rows = list(csv.DictReader(f))
detected = sum(int(r['detected']) for r in rows)
silent = sum(int(r['silent_corruption']) for r in rows)
print(f'Coverage: {detected}/{len(rows)} = {detected/len(rows):.2%}; silent={silent}')
print(f'CSV: {csvfile}')
print('SCOPE: Only standalone W=128 residue checker. Mode and width are labels; no FLALM GMM/SMM RTL is simulated.')
