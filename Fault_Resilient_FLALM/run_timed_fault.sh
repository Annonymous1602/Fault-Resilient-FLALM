#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
python3 scripts/make_timed_fault_tests.py
for n in 1024 2048; do
  iverilog -g2012 -s flalm_core_fault_tb_${n} -o build/timed_fault_${n}.vvp \
    secure_rtl/*.v security/karatsuba_residue_monitor.v \
    fault_injection/flalm_core_fault_tb_${n}.v
  for mode in GMM SMM; do
    echo "===== TIMED CORE FAULT: $n $mode ====="
    vvp build/timed_fault_${n}.vvp +target=${mode} | tee logs/timed_fault_${n}_${mode}.log
    grep -q 'FAULT_TEST_PASS detected=1' logs/timed_fault_${n}_${mode}.log
    grep -q '^TIMING start_edge=' logs/timed_fault_${n}_${mode}.log
  done
done
