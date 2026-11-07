#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
if [ ! -f secure_rtl/karatsuba.v ]; then echo 'Missing secure_rtl'; exit 1; fi
python3 scripts/make_core_fault_tb.py
python3 scripts/make_containment_tbs.py
for n in 1024 2048; do
  for kind in normal fault; do
    top="containment_${kind}_tb_${n}"
    iverilog -g2012 -s "$top" -o "build/${top}.vvp" \
      secure_rtl/*.v security/karatsuba_residue_monitor.v \
      security/flalm_secure.v "fault_injection/${top}.v"
    if [ "$kind" = normal ]; then
      vvp "build/${top}.vvp" | tee "logs/${top}.log"
      grep -q 'RESULT: PASS' "logs/${top}.log"
      if grep -qE 'CONTAINMENT_FAIL|RESULT: FAIL' "logs/${top}.log"; then exit 1; fi
    else
      for mode in GMM SMM; do
        vvp "build/${top}.vvp" +target="$mode" | tee "logs/${top}_${mode}.log"
        grep -q 'CONTAINMENT_PASS fault rejected' "logs/${top}_${mode}.log"
        grep -q 'FAULT_TEST_PASS' "logs/${top}_${mode}.log"
      done
    fi
  done
done
echo 'PASS: containment normal tests and four targeted faults'
