#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/make_synth_ready.py
mkdir -p build logs results/synthesis
for n in 1024 2048; do
  tb="secure_flalm_tb_${n}"
  echo "VERIFY ${n}-bit explicit alarm ports"
  iverilog -g2012 -s "$tb" -o "build/phase9_${n}.vvp" synth_secure_rtl/*.v security/karatsuba_residue_monitor.v "tb/${tb}.v"
  vvp "build/phase9_${n}.vvp" | tee "logs/phase9_${n}.log"
  grep -q 'SECURITY PASS:' "logs/phase9_${n}.log"
  grep -q 'RESULT: PASS' "logs/phase9_${n}.log"
done
echo 'PASS: functional tests with explicit alarm ports'
if ! command -v vivado >/dev/null 2>&1; then
  echo 'Vivado not found on PATH; only functional verification completed.'
  exit 0
fi
for n in 1024 2048; do
  nw=$((n/128))
  for variant in baseline secure; do
    echo "SYNTHESIS $variant $n"
    vivado -mode batch -nojournal -nolog -source scripts/vivado_phase9.tcl -tclargs "$variant" "$nw" | tee "logs/vivado_${variant}_${n}.log"
    grep -q SYNTH_DONE "logs/vivado_${variant}_${n}.log"
  done
done
