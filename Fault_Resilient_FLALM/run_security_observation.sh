#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build logs

for n in 1024 2048
do
    echo "======================================="
    echo "SECURITY OBSERVATION: $n-bit FLALM"
    echo "======================================="

    iverilog -g2012 \
        -s secure_flalm_tb_${n} \
        -o build/security_observe_${n}.vvp \
        secure_rtl/*.v \
        security/karatsuba_residue_monitor.v \
        tb/secure_flalm_tb_${n}.v

    vvp build/security_observe_${n}.vvp \
        | tee logs/security_observe_${n}.log

    grep -q "SECURITY PASS:" \
        logs/security_observe_${n}.log

    grep -q "RESULT: PASS" \
        logs/security_observe_${n}.log

    if grep -qE "SECURITY FAIL|RESULT: FAIL|ERROR" \
        logs/security_observe_${n}.log; then

        echo "Security verification FAILED"
        exit 1
    fi

done

echo "======================================="
echo "ALL SECURITY OBSERVATION TESTS PASSED"
echo "======================================="
