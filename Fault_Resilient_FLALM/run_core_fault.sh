#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
python3 scripts/make_core_fault_tb.py
for n in 1024 2048; do
  iverilog -g2012 -s flalm_core_fault_tb_${n} -o build/core_fault_${n}.vvp \
    secure_rtl/*.v security/karatsuba_residue_monitor.v \
    fault_injection/flalm_core_fault_tb_${n}.v
  for mode in GMM SMM; do
    echo "===== CORE FAULT: ${n} ${mode} ====="
    vvp build/core_fault_${n}.vvp +target=${mode} | tee logs/core_fault_${n}_${mode}.log
    grep -q 'FAULT_TEST_PASS detected=1' logs/core_fault_${n}_${mode}.log || {
      echo "FAIL: ${n} ${mode}"; exit 1;
    }
  done
done
echo 'ALL FOUR TARGETED CORE FAULT TESTS PASSED'
