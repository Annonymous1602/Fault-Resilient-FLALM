#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
iverilog -g2012 -s residue_mul_check_tb -o build/checker.vvp security/residue_mul_check.v tb/residue_mul_check_tb.v
vvp build/checker.vvp | tee logs/checker.log
