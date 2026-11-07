#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
for n in 1024 2048; do
  echo "===== SECURE ${n}-BIT FUNCTIONAL TEST ====="
  iverilog -g2012 -s "flalm_tb_${n}" -o "build/secure_${n}.vvp" \
    secure_rtl/*.v security/karatsuba_residue_monitor.v "baseline/tb/flalm_tb_${n}.v"
  vvp "build/secure_${n}.vvp" | tee "logs/secure_${n}.log"
  if ! grep -q 'RESULT: PASS' "logs/secure_${n}.log"; then
    echo "ERROR: Functional baseline did not pass for $n" >&2; exit 1
  fi
  echo "IMPORTANT: Run the monitor observation test as well; normal TB alone does not inspect alarms."
done
