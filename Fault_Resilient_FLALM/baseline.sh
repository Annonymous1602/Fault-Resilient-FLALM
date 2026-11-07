#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null || { echo 'Install iverilog: sudo apt install iverilog'; exit 1; }
mkdir -p build logs
for bits in 1024 2048; do
  echo "=== FLALM baseline ${bits} ==="
  iverilog -g2012 -s "flalm_tb_${bits}" -o "build/base_${bits}.vvp" baseline/rtl/*.v "baseline/tb/flalm_tb_${bits}.v"
  vvp "build/base_${bits}.vvp" | tee "logs/base_${bits}.log"
  if grep -q '^FAIL' "logs/base_${bits}.log"; then echo "FAILED ${bits}"; exit 1; fi
  if ! grep -q '^PASS' "logs/base_${bits}.log"; then echo "No PASS lines; check testbench"; exit 1; fi
done
